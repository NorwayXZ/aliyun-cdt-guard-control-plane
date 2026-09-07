#!/usr/bin/env python3
"""Ordered Alibaba Cloud ECS/EIP failover deployment queue."""
import fcntl
import json
import os
import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

BASE_DIR = Path(os.environ.get("CDT_GUARD_HOME", "/opt/aliyun-cdt-guard-control-plane"))
CONFIG_FILE = BASE_DIR / "instances.json"
STATE_FILE = BASE_DIR / "deployment_state.json"
LOCK_FILE = BASE_DIR / "deployment.lock"
ECS_DOMAIN = "ecs.aliyuncs.com"
VPC_DOMAIN = "vpc.aliyuncs.com"
ECS_VERSION = "2014-05-26"
VPC_VERSION = "2016-04-28"


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def read_json(path: Path, default: dict) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else default
    except Exception:
        return default


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def defaults() -> dict:
    return {
        "enabled": False,
        "auto_failover": False,
        "open_all_ports": True,
        "instance_cpu": 2,
        "instance_memory_gb": 0.5,
        "system_disk_gb": 2,
        "instance_charge_type": "PrePaid",
        "eip_isp": "BGP_PRO",
        "eip_charge_type": "PayByTraffic",
        "eip_bandwidth_mbps": 200,
        "accounts": [],
    }


def settings(config: dict) -> dict:
    result = defaults()
    raw = config.get("deployment") or {}
    if isinstance(raw, dict):
        result.update({key: value for key, value in raw.items() if key != "accounts"})
        result["accounts"] = [item for item in raw.get("accounts", []) if isinstance(item, dict)]
    return result


def request(client, domain: str, version: str, action: str, params: dict[str, Any]) -> dict:
    from aliyunsdkcore.request import CommonRequest
    api = CommonRequest()
    api.set_domain(domain)
    api.set_version(version)
    api.set_action_name(action)
    api.set_method("POST")
    api.set_accept_format("json")
    for key, value in params.items():
        if value is not None and value != "":
            api.add_query_param(key, str(value))
    return json.loads(client.do_action_with_exception(api).decode("utf-8"))


def client(account: dict):
    from aliyunsdkcore.client import AcsClient
    return AcsClient(account["access_key_id"], account["access_key_secret"], account["region_id"])


def select_instance_type(api, region_id: str, cpu: int, memory_gb: float) -> str:
    payload = request(api, ECS_DOMAIN, ECS_VERSION, "DescribeInstanceTypes", {"RegionId": region_id})
    rows = ((payload.get("InstanceTypes") or {}).get("InstanceType") or [])
    candidates = []
    for item in rows:
        try:
            if int(item.get("CpuCoreCount")) == cpu and float(item.get("MemorySize")) == memory_gb:
                candidates.append(str(item.get("InstanceTypeId") or ""))
        except (TypeError, ValueError):
            continue
    candidates = sorted(item for item in candidates if item)
    if not candidates:
        raise RuntimeError(f"该地域没有严格匹配 {cpu}C/{memory_gb}G 的实例规格")
    return candidates[0]


def create_security_group(api, account: dict) -> str:
    region = account["region_id"]
    group_name = f"cdt-deploy-{secrets.token_hex(4)}"
    response = request(api, ECS_DOMAIN, ECS_VERSION, "CreateSecurityGroup", {
        "RegionId": region,
        "VpcId": account["vpc_id"],
        "SecurityGroupName": group_name,
        "Description": "Auto-created deployment security group",
    })
    group_id = str(response.get("SecurityGroupId") or "")
    if not group_id:
        raise RuntimeError("创建安全组未返回 SecurityGroupId")
    for protocol, ports in (("tcp", "1/65535"), ("udp", "1/65535")):
        request(api, ECS_DOMAIN, ECS_VERSION, "AuthorizeSecurityGroup", {
            "RegionId": region,
            "SecurityGroupId": group_id,
            "IpProtocol": protocol,
            "PortRange": ports,
            "SourceCidrIp": "0.0.0.0/0",
            "NicType": "intranet",
            "Policy": "accept",
        })
    return group_id


def launch_account(account: dict, config: dict) -> dict:
    required = ("access_key_id", "access_key_secret", "region_id", "image_id", "vpc_id", "vswitch_id")
    missing = [key for key in required if not str(account.get(key) or "").strip()]
    if missing:
        raise RuntimeError("缺少部署配置：" + ", ".join(missing))
    api = client(account)
    deployment = settings(config)
    instance_type = str(account.get("instance_type") or "") or select_instance_type(
        api, account["region_id"], int(deployment["instance_cpu"]), float(deployment["instance_memory_gb"]),
    )
    security_group_id = str(account.get("security_group_id") or "")
    if not security_group_id:
        security_group_id = create_security_group(api, account)
    password = secrets.token_urlsafe(18)
    response = request(api, ECS_DOMAIN, ECS_VERSION, "RunInstances", {
        "RegionId": account["region_id"],
        "ImageId": account["image_id"],
        "InstanceType": instance_type,
        "VSwitchId": account["vswitch_id"],
        "SecurityGroupId": security_group_id,
        "InstanceChargeType": deployment["instance_charge_type"],
        "Period": 1,
        "PeriodUnit": "Month",
        "SystemDisk.Size": account.get("system_disk_gb") or deployment["system_disk_gb"],
        "SystemDisk.Category": account.get("system_disk_category") or "cloud_efficiency",
        "Password": password,
        "InstanceName": f"auto-{account.get('label') or account.get('id')}",
        "Amount": 1,
    })
    instance_ids = (response.get("InstanceIdSets") or {}).get("InstanceIdSet") or []
    if not instance_ids:
        raise RuntimeError("创建实例未返回 InstanceId")
    instance_id = str(instance_ids[0])
    eip = request(api, VPC_DOMAIN, VPC_VERSION, "AllocateEipAddress", {
        "RegionId": account["region_id"],
        "Bandwidth": account.get("eip_bandwidth_mbps") or deployment["eip_bandwidth_mbps"],
        "InternetChargeType": account.get("eip_charge_type") or deployment["eip_charge_type"],
        "ISP": account.get("eip_isp") or deployment["eip_isp"],
        "InstanceChargeType": "PostPaid",
    })
    allocation_id = str(eip.get("AllocationId") or "")
    if not allocation_id:
        raise RuntimeError("创建精品 BGP EIP 未返回 AllocationId")
    request(api, VPC_DOMAIN, VPC_VERSION, "AssociateEipAddress", {
        "RegionId": account["region_id"], "AllocationId": allocation_id, "InstanceId": instance_id,
    })
    return {
        "account_id": str(account.get("id") or ""),
        "account_label": str(account.get("label") or account.get("id") or ""),
        "region_id": account["region_id"],
        "instance_id": instance_id,
        "instance_type": instance_type,
        "security_group_id": security_group_id,
        "eip_allocation_id": allocation_id,
        "eip_address": eip.get("EipAddress") or eip.get("IpAddress") or "",
        "password": password,
    }


def deployment_accounts(config: dict, after_account_id: str = "") -> list[dict]:
    accounts = [item for item in settings(config)["accounts"] if item.get("enabled", True)]
    accounts.sort(key=lambda item: (int(item.get("priority") or 9999), str(item.get("label") or "")))
    if after_account_id:
        for index, item in enumerate(accounts):
            if str(item.get("id") or "") == after_account_id:
                return accounts[index + 1:]
    return accounts


def persist_instance(config: dict, result: dict) -> None:
    server_id = f"auto-{result['account_id']}-{result['instance_id'][-8:]}"
    instance = {
        "id": server_id,
        "label": f"{result['account_label']} 自动实例",
        "product_name": f"{result['account_label']} 自动实例",
        "instance_id": result["instance_id"],
        "region_id": result["region_id"],
        "access_key_id": next(item["access_key_id"] for item in settings(config)["accounts"] if str(item.get("id")) == result["account_id"]),
        "access_key_secret": next(item["access_key_secret"] for item in settings(config)["accounts"] if str(item.get("id")) == result["account_id"]),
        "eip_allocation_id": result["eip_allocation_id"],
        "ssh_user": "root",
        "ssh_password": result["password"],
        "notes": f"自动部署 · {result['instance_type']} · EIP {result['eip_address']}",
        "enabled": True,
    }
    config.setdefault("instances", []).append(instance)
    write_json(CONFIG_FILE, config)
    state = read_json(STATE_FILE, {})
    state.update({"active_account_id": result["account_id"], "active_instance_id": result["instance_id"], "last_success": result, "updated_at": now()})
    write_json(STATE_FILE, state)


def deploy_next(after_account_id: str = "") -> dict:
    with LOCK_FILE.open("a+") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {"ok": False, "error": "已有部署任务正在运行"}
        config = read_json(CONFIG_FILE, {})
        if not settings(config)["enabled"]:
            return {"ok": False, "error": "自动部署模块尚未启用"}
        attempts = []
        for account in deployment_accounts(config, after_account_id):
            try:
                result = launch_account(account, config)
                persist_instance(config, result)
                attempts.append({"account_id": account.get("id"), "ok": True})
                return {"ok": True, "result": result, "attempts": attempts}
            except Exception as exc:
                attempts.append({"account_id": account.get("id"), "ok": False, "error": str(exc)})
        state = read_json(STATE_FILE, {})
        state.update({"last_failure": {"at": now(), "attempts": attempts}, "updated_at": now()})
        write_json(STATE_FILE, state)
        return {"ok": False, "error": "所有账号均未能创建实例", "attempts": attempts}


def should_failover(status: dict, previous_status: dict | None) -> bool:
    state = read_json(STATE_FILE, {})
    active = str(state.get("active_instance_id") or "")
    if not active or not previous_status:
        return False
    previous = next((item for item in previous_status.get("instances", []) if str(item.get("instance_id")) == active), {})
    current = next((item for item in status.get("instances", []) if str(item.get("instance_id")) == active), {})
    if previous.get("instance_status") != "Running":
        return False
    if current.get("manual_stop") or current.get("action") in {"stop", "manual_stop", "keep_stopped"}:
        return False
    return not current or current.get("instance_status") in {"Stopped", "Stopping", None}


def handle_failover(status: dict, previous_status: dict | None) -> dict | None:
    config = read_json(CONFIG_FILE, {})
    deployment = settings(config)
    if not deployment["enabled"] or not deployment["auto_failover"] or not should_failover(status, previous_status):
        return None
    state = read_json(STATE_FILE, {})
    return deploy_next(str(state.get("active_account_id") or ""))
