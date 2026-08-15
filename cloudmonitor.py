#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Small CloudMonitor adapter for near-real-time outbound traffic samples."""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from typing import Any

from aliyunsdkcore.client import AcsClient
from aliyunsdkcore.request import CommonRequest


GB = 1024 ** 3
DEFAULT_PERIOD_SECONDS = 60
DEFAULT_WINDOW_MINUTES = 10


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _monitor_domain(region_id: str | None) -> str:
    configured = os.environ.get("CLOUD_MONITOR_ENDPOINT", "").strip()
    if configured:
        return configured
    region = str(region_id or "").strip()
    if region:
        return f"metrics.{region}.aliyuncs.com"
    return "metrics.cn-hangzhou.aliyuncs.com"


def _datapoints(payload: dict[str, Any]) -> list[dict[str, Any]]:
    raw = payload.get("Datapoints") or payload.get("datapoints") or []
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            return []
    if isinstance(raw, dict):
        raw = raw.get("Datapoint") or raw.get("datapoints") or []
    return [item for item in raw if isinstance(item, dict)]


def _point_timestamp(point: dict[str, Any]) -> float:
    value = point.get("timestamp", point.get("Timestamp", 0))
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0
    return number / 1000 if number > 10_000_000_000 else number


def _point_value(point: dict[str, Any]) -> float:
    for key in ("Value", "value", "Sum", "sum", "Average", "average", "Maximum", "maximum"):
        try:
            return max(0.0, float(point.get(key)))
        except (TypeError, ValueError):
            continue
    return 0.0


def _point_time_iso(timestamp: float) -> str | None:
    if timestamp <= 0:
        return None
    return datetime.fromtimestamp(timestamp, timezone.utc).isoformat(timespec="seconds")


def _query_metric_list(
    client: AcsClient,
    region_id: str,
    namespace: str,
    metric_name: str,
    dimensions: dict[str, str],
    period_seconds: int = DEFAULT_PERIOD_SECONDS,
    window_minutes: int = DEFAULT_WINDOW_MINUTES,
) -> list[dict[str, Any]]:
    now = datetime.now(timezone.utc)
    start = now - timedelta(minutes=max(2, window_minutes))
    request = CommonRequest()
    request.set_domain(_monitor_domain(region_id))
    request.set_version("2019-01-01")
    request.set_action_name("DescribeMetricList")
    request.set_method("POST")
    request.set_accept_format("json")
    request.add_query_param("Namespace", namespace)
    request.add_query_param("MetricName", metric_name)
    request.add_query_param("Dimensions", json.dumps([dimensions], separators=(",", ":")))
    request.add_query_param("StartTime", start.strftime("%Y-%m-%dT%H:%M:%SZ"))
    request.add_query_param("EndTime", now.strftime("%Y-%m-%dT%H:%M:%SZ"))
    request.add_query_param("Period", str(max(60, period_seconds)))
    request.add_query_param("Length", str(max(10, window_minutes + 2)))
    response = client.do_action_with_exception(request)
    payload = json.loads(response.decode("utf-8"))
    return _datapoints(payload)


def _empty_result(enabled: bool = True, error: str | None = None) -> dict[str, Any]:
    return {
        "realtime_monitor_enabled": enabled,
        "realtime_monitor_source": None,
        "realtime_monitor_namespace": None,
        "realtime_monitor_metric": None,
        "realtime_last_minute_gb": None,
        "realtime_window_gb": None,
        "realtime_out_mbps": None,
        "realtime_updated_at": None,
        "realtime_collected_at": _iso_now(),
        "realtime_error": error,
    }


def query_realtime_traffic(
    client: AcsClient,
    item: dict[str, Any],
) -> dict[str, Any]:
    """Return a best-effort near-real-time sample without breaking CDT checks."""
    enabled = bool(item.get("realtime_monitoring", True))
    if not enabled:
        return _empty_result(False, "实时监控已关闭")

    region_id = str(item.get("region_id") or "")
    source = str(item.get("realtime_monitor_source") or "auto").strip().lower()
    eip_id = str(item.get("eip_allocation_id") or "").strip()

    if source not in {"auto", "ecs", "eip"}:
        source = "auto"
    if source == "eip" and not eip_id:
        return _empty_result(True, "已选择 EIP 监控，但未填写 EIP AllocationId")

    if source == "eip" or (source == "auto" and eip_id):
        namespace = "acs_vpc_eip"
        metric_name = "net.tx"
        dimensions = {"instanceId": eip_id}
        source_label = "EIP net.tx"
        source_key = "eip"
    else:
        namespace = "acs_ecs_dashboard"
        metric_name = "InternetOut"
        dimensions = {"instanceId": str(item.get("instance_id") or "")}
        source_label = "ECS InternetOut"
        source_key = "ecs"

    if not dimensions["instanceId"]:
        return _empty_result(True, f"{source_label} 缺少资源 ID")

    try:
        points = _query_metric_list(
            client,
            region_id,
            namespace,
            metric_name,
            dimensions,
            period_seconds=int(item.get("realtime_period_seconds") or DEFAULT_PERIOD_SECONDS),
            window_minutes=int(item.get("realtime_window_minutes") or DEFAULT_WINDOW_MINUTES),
        )
        normalized = sorted(
            (
                (_point_timestamp(point), _point_value(point))
                for point in points
                if _point_timestamp(point) > 0
            ),
            key=lambda row: row[0],
        )
        if not normalized:
            return {
                **_empty_result(True, "CloudMonitor 暂无可用数据点"),
                "realtime_monitor_source": source_key,
                "realtime_monitor_namespace": namespace,
                "realtime_monitor_metric": metric_name,
            }
        latest_timestamp, latest_bytes = normalized[-1]
        period_seconds = max(60, int(item.get("realtime_period_seconds") or DEFAULT_PERIOD_SECONDS))
        return {
            "realtime_monitor_enabled": True,
            "realtime_monitor_source": source_key,
            "realtime_monitor_source_label": source_label,
            "realtime_monitor_namespace": namespace,
            "realtime_monitor_metric": metric_name,
            "realtime_last_minute_gb": latest_bytes / GB,
            "realtime_window_gb": sum(value for _, value in normalized) / GB,
            "realtime_out_mbps": latest_bytes * 8 / period_seconds / 1_000_000,
            "realtime_updated_at": _point_time_iso(latest_timestamp),
            "realtime_collected_at": _iso_now(),
            "realtime_error": None,
        }
    except Exception as exc:
        return {
            **_empty_result(True, str(exc)[:500]),
            "realtime_monitor_source": source_key,
            "realtime_monitor_source_label": source_label,
            "realtime_monitor_namespace": namespace,
            "realtime_monitor_metric": metric_name,
        }
