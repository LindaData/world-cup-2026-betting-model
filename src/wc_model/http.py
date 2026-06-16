from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


@dataclass(frozen=True)
class HttpResponse:
    url: str
    status_code: int
    headers: dict[str, str]
    text: str

    def json(self) -> Any:
        return json.loads(self.text)

    @property
    def ok(self) -> bool:
        return 200 <= self.status_code < 300


class HttpClient:
    def __init__(
        self,
        base_url: str = "",
        headers: dict[str, str] | None = None,
        timeout_seconds: int = 30,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.headers = headers or {}
        self.timeout_seconds = timeout_seconds

    def get(self, path_or_url: str, params: dict[str, Any] | None = None) -> HttpResponse:
        url = self._build_url(path_or_url, params)
        request = Request(url, headers=self.headers, method="GET")
        try:
            with urlopen(request, timeout=self.timeout_seconds) as response:
                text = response.read().decode("utf-8")
                return HttpResponse(
                    url=url,
                    status_code=response.status,
                    headers=dict(response.headers.items()),
                    text=text,
                )
        except HTTPError as exc:
            text = exc.read().decode("utf-8", errors="replace")
            return HttpResponse(
                url=url,
                status_code=exc.code,
                headers=dict(exc.headers.items()) if exc.headers else {},
                text=text,
            )
        except URLError as exc:
            raise ConnectionError(f"Request failed for {url}: {exc.reason}") from exc

    def download(self, url: str, destination: Path) -> HttpResponse:
        response = self.get(url)
        if response.ok:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(response.text, encoding="utf-8")
        return response

    def download_bytes(self, url: str, destination: Path) -> HttpResponse:
        request = Request(url, headers=self.headers, method="GET")
        try:
            with urlopen(request, timeout=self.timeout_seconds) as response:
                content = response.read()
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(content)
                return HttpResponse(
                    url=url,
                    status_code=response.status,
                    headers=dict(response.headers.items()),
                    text=f"<binary {len(content)} bytes>",
                )
        except HTTPError as exc:
            text = exc.read().decode("utf-8", errors="replace")
            return HttpResponse(
                url=url,
                status_code=exc.code,
                headers=dict(exc.headers.items()) if exc.headers else {},
                text=text,
            )
        except URLError as exc:
            raise ConnectionError(f"Request failed for {url}: {exc.reason}") from exc

    def _build_url(self, path_or_url: str, params: dict[str, Any] | None) -> str:
        if path_or_url.startswith(("http://", "https://")):
            url = path_or_url
        elif self.base_url:
            url = f"{self.base_url}/{path_or_url.lstrip('/')}"
        else:
            url = path_or_url

        if params:
            clean_params = {key: value for key, value in params.items() if value not in (None, "")}
            if clean_params:
                separator = "&" if "?" in url else "?"
                url = f"{url}{separator}{urlencode(clean_params, doseq=True)}"
        return url
