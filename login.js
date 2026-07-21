const form = document.getElementById("loginForm");
const error = document.getElementById("loginError");
const notice = document.getElementById("loginNotice");

form.addEventListener("submit", (event) => {
  event.preventDefault();

  const account = document.getElementById("account").value.trim();
  const password = document.getElementById("password").value.trim();

  if (!account || !password) {
    error.classList.add("show");
    return;
  }

  error.classList.remove("show");
  notice.classList.add("show");
  window.setTimeout(() => notice.classList.remove("show"), 2800);
});
