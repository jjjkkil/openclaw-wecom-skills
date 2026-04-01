"""
Smartsheet API Client

Low-level API client for WeChat Enterprise Smartsheet (智能表格) operations.
Handles HTTP requests and access token management.
"""

import json
import os
import requests
import time
import logging
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

# Token error codes that require refresh / re-fetch
TOKEN_ERROR_CODES = {40014, 42001, 42002}

# Buffer seconds before actual expiry to treat token as expired
TOKEN_EXPIRE_BUFFER = 300


class SmartsheetAPIError(Exception):
    """Smartsheet API error."""
    def __init__(self, errcode: int, errmsg: str):
        self.errcode = errcode
        self.errmsg = errmsg
        super().__init__(f"[{errcode}] {errmsg}")


class SmartsheetClient:
    """
    Low-level API client for WeChat Enterprise Smartsheet.

    Handles:
    - Access token management (reads from config.json, writes on refresh)
    - HTTP request/response handling
    - Error handling and automatic token retry
    """

    BASE_URL = "https://qyapi.weixin.qq.com/cgi-bin"
    DEFAULT_CONFIG_PATH = os.path.expanduser("~/.openclaw/workspace-app-evaluation/config.json")

    def __init__(
        self,
        corpid: str,
        corpsecret: str,
        proxy_url: Optional[str] = None,
        config_path: Optional[str] = None
    ):
        """
        Initialize Smartsheet API client.

        Args:
            corpid: Enterprise WeChat Corp ID
            corpsecret: Application secret for Smartsheet access
            proxy_url: HTTP proxy URL (optional)
            config_path: Path to config.json (optional, uses default if not given)
        """
        self.corpid = corpid
        self.corpsecret = corpsecret
        self.proxy_url = proxy_url
        self.config_path = config_path or self.DEFAULT_CONFIG_PATH
        self._access_token: Optional[str] = None
        self._token_expires_at: int = 0
        self._load_token_from_config()

    # ------------------------------------------------------------------
    # config.json read / write helpers
    # ------------------------------------------------------------------
    def _read_config(self) -> Dict:
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def _write_config(self, cfg: Dict) -> None:
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(cfg, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.warning(f"Failed to write config.json: {e}")

    def _load_token_from_config(self) -> None:
        cfg = self._read_config()
        token = cfg.get("wecom", {}).get("access_token")
        expires_at = cfg.get("wecom", {}).get("expires_at", 0)
        if token and time.time() < (expires_at - TOKEN_EXPIRE_BUFFER):
            self._access_token = token
            self._token_expires_at = expires_at

    def _save_token_to_config(self, token: str, expires_in: int) -> None:
        cfg = self._read_config()
        now = time.time()
        expires_at = now + expires_in - TOKEN_EXPIRE_BUFFER
        if "wecom" not in cfg:
            cfg["wecom"] = {}
        cfg["wecom"]["access_token"] = token
        cfg["wecom"]["expires_at"] = expires_at
        cfg["wecom"]["token_updated_at"] = now
        self._write_config(cfg)

    # ------------------------------------------------------------------
    # Token fetch
    # ------------------------------------------------------------------
    def _fetch_token_from_api(self) -> Dict:
        """Call WeChat Enterprise /cgi-bin/gettoken and return full response dict."""
        url = f"{self.BASE_URL}/gettoken"
        params = {"corpid": self.corpid, "corpsecret": self.corpsecret}
        proxies = {"http": self.proxy_url, "https": self.proxy_url} if self.proxy_url else None
        resp = requests.get(url, params=params, timeout=10, proxies=proxies)
        return resp.json()

    def get_access_token(self) -> str:
        """
        Return a valid access token (from memory or config.json).
        Refreshes from API if the cached token is missing or expired.
        """
        if self._access_token and time.time() < (self._token_expires_at - TOKEN_EXPIRE_BUFFER):
            return self._access_token

        data = self._fetch_token_from_api()
        errcode = data.get("errcode", 0)
        if errcode != 0:
            raise SmartsheetAPIError(errcode, data.get("errmsg", "Failed to get token"))

        token = data["access_token"]
        expires_in = data.get("expires_in", 7200)
        self._access_token = token
        self._token_expires_at = time.time() + expires_in
        self._save_token_to_config(token, expires_in)
        logger.info(f"Token refreshed, expires in {expires_in}s")
        return token

    def _request(
        self,
        method: str,
        endpoint: str,
        body: Dict = None,
        timeout: int = 30
    ) -> Dict:
        """
        Make an authenticated API request with automatic token retry on token errors.

        Args:
            method: HTTP method (GET or POST)
            endpoint: API endpoint path
            body: Request body for POST requests
            timeout: Request timeout in seconds

        Returns:
            API response dict

        Raises:
            SmartsheetAPIError: If request fails after token refresh
        """
        access_token = self.get_access_token()
        url = f"{self.BASE_URL}{endpoint}"
        params = {"access_token": access_token}

        try:
            proxies = {"http": self.proxy_url, "https": self.proxy_url} if self.proxy_url else None

            if method.upper() == "GET":
                response = requests.get(url, params=params, timeout=timeout, proxies=proxies)
            else:
                response = requests.post(
                    url, params=params, json=body, timeout=timeout, proxies=proxies
                )

            data = response.json()

            errcode = data.get("errcode", 0)

            # Token error → refresh and retry once
            if errcode in TOKEN_ERROR_CODES:
                logger.warning(f"Token error {errcode}, refreshing and retrying...")
                self._access_token = None   # force re-fetch
                access_token = self.get_access_token()
                params = {"access_token": access_token}
                if method.upper() == "GET":
                    response = requests.get(url, params=params, timeout=timeout, proxies=proxies)
                else:
                    response = requests.post(
                        url, params=params, json=body, timeout=timeout, proxies=proxies
                    )
                data = response.json()
                errcode = data.get("errcode", 0)

            if errcode != 0:
                raise SmartsheetAPIError(
                    data.get("errcode", -1),
                    data.get("errmsg", "Unknown error")
                )

            return data

        except requests.RequestException as e:
            raise SmartsheetAPIError(-1, f"Network error: {str(e)}")

    # ==================== Sheet Operations ====================

    def add_sheet(
        self,
        docid: str,
        title: str = None,
        index: int = None
    ) -> Dict:
        """添加子表。"""
        body = {"docid": docid}

        properties = {}
        if title is not None:
            properties["title"] = title
        if index is not None:
            properties["index"] = index

        if properties:
            body["properties"] = properties

        return self._request("POST", "/wedoc/smartsheet/add_sheet", body)

    def delete_sheet(self, docid: str, sheet_id: str) -> Dict:
        """删除子表。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id
        }
        return self._request("POST", "/wedoc/smartsheet/del_sheet", body)

    def update_sheet(self, docid: str, sheet_id: str, title: str = None) -> Dict:
        """更新子表。"""
        properties = {"sheet_id": sheet_id}
        if title is not None:
            properties["title"] = title

        body = {
            "docid": docid,
            "properties": properties
        }
        return self._request("POST", "/wedoc/smartsheet/update_sheet", body)

    def get_sheets(
        self,
        docid: str,
        sheet_id: str = None,
        need_all_type_sheet: bool = False
    ) -> Dict:
        """查询子表。"""
        body = {"docid": docid}

        if sheet_id is not None:
            body["sheet_id"] = sheet_id
        if need_all_type_sheet:
            body["need_all_type_sheet"] = True

        return self._request("POST", "/wedoc/smartsheet/get_sheets", body)

    # ==================== View Operations ====================

    def add_view(
        self,
        docid: str,
        sheet_id: str,
        view_title: str,
        view_type: str,
        property_gantt: Dict = None,
        property_calendar: Dict = None
    ) -> Dict:
        """添加视图。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "view_title": view_title,
            "view_type": view_type
        }

        if property_gantt is not None:
            body["property_gantt"] = property_gantt
        if property_calendar is not None:
            body["property_calendar"] = property_calendar

        return self._request("POST", "/wedoc/smartsheet/add_view", body)

    def delete_view(
        self,
        docid: str,
        sheet_id: str,
        view_id: str
    ) -> Dict:
        """删除视图。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "view_id": view_id
        }
        return self._request("POST", "/wedoc/smartsheet/del_view", body)

    def update_view(
        self,
        docid: str,
        sheet_id: str,
        view_id: str,
        view_title: str = None,
        property: Dict = None
    ) -> Dict:
        """更新视图。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "view_id": view_id
        }

        if view_title is not None:
            body["view_title"] = view_title
        if property is not None:
            body["property"] = property

        return self._request("POST", "/wedoc/smartsheet/update_view", body)

    def get_views(
        self,
        docid: str,
        sheet_id: str,
        view_ids: List[str] = None,
        offset: int = 0,
        limit: int = 0
    ) -> Dict:
        """查询视图。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id
        }

        if view_ids is not None:
            body["view_ids"] = view_ids
        if offset > 0:
            body["offset"] = offset
        if limit > 0:
            body["limit"] = min(limit, 1000)

        return self._request("POST", "/wedoc/smartsheet/get_views", body)

    # ==================== Field Operations ====================

    def add_fields(
        self,
        docid: str,
        sheet_id: str,
        fields: List[Dict]
    ) -> Dict:
        """添加字段。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "fields": fields
        }
        return self._request("POST", "/wedoc/smartsheet/add_fields", body)

    def delete_fields(
        self,
        docid: str,
        sheet_id: str,
        field_ids: List[str]
    ) -> Dict:
        """删除字段。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "field_ids": field_ids
        }
        return self._request("POST", "/wedoc/smartsheet/del_fields", body)

    def update_fields(
        self,
        docid: str,
        sheet_id: str,
        fields: List[Dict]
    ) -> Dict:
        """更新字段。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "fields": fields
        }
        return self._request("POST", "/wedoc/smartsheet/update_fields", body)

    def get_fields(
        self,
        docid: str,
        sheet_id: str,
        view_id: str = None,
        field_ids: List[str] = None,
        field_titles: List[str] = None,
        offset: int = 0,
        limit: int = 0
    ) -> Dict:
        """查询字段。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id
        }

        if view_id is not None:
            body["view_id"] = view_id
        if field_ids is not None:
            body["field_ids"] = field_ids
        if field_titles is not None:
            body["field_titles"] = field_titles
        if offset > 0:
            body["offset"] = offset
        if limit > 0:
            body["limit"] = min(limit, 1000)

        return self._request("POST", "/wedoc/smartsheet/get_fields", body)

    # ==================== Record Operations ====================

    def add_records(
        self,
        docid: str,
        sheet_id: str,
        records: List[Dict],
        key_type: str = "CELL_VALUE_KEY_TYPE_FIELD_TITLE"
    ) -> Dict:
        """添加记录。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "key_type": key_type,
            "records": records
        }
        return self._request("POST", "/wedoc/smartsheet/add_records", body)

    def delete_records(
        self,
        docid: str,
        sheet_id: str,
        record_ids: List[str]
    ) -> Dict:
        """删除记录。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "record_ids": record_ids
        }
        return self._request("POST", "/wedoc/smartsheet/del_records", body)

    def update_records(
        self,
        docid: str,
        sheet_id: str,
        records: List[Dict],
        key_type: str = "CELL_VALUE_KEY_TYPE_FIELD_TITLE"
    ) -> Dict:
        """更新记录。"""
        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "key_type": key_type,
            "records": records
        }
        return self._request("POST", "/wedoc/smartsheet/update_records", body)

    def get_records(
        self,
        docid: str,
        sheet_id: str,
        view_id: str = None,
        record_ids: List[str] = None,
        key_type: str = "CELL_VALUE_KEY_TYPE_FIELD_TITLE",
        field_titles: List[str] = None,
        field_ids: List[str] = None,
        sort: List[Dict] = None,
        offset: int = 0,
        limit: int = 0,
        filter_spec: Dict = None
    ) -> Dict:
        """查询记录。"""
        if sort is not None and filter_spec is not None:
            raise ValueError("sort and filter_spec cannot be used together")

        body = {
            "docid": docid,
            "sheet_id": sheet_id,
            "key_type": key_type
        }

        if view_id is not None:
            body["view_id"] = view_id
        if record_ids is not None:
            body["record_ids"] = record_ids
        if field_titles is not None:
            body["field_titles"] = field_titles
        if field_ids is not None:
            body["field_ids"] = field_ids
        if sort is not None:
            body["sort"] = sort
        if offset > 0:
            body["offset"] = offset
        if limit > 0:
            body["limit"] = min(limit, 1000)
        if filter_spec is not None:
            body["filter_spec"] = filter_spec

        return self._request("POST", "/wedoc/smartsheet/get_records", body)

    def get_all_records(
        self,
        docid: str,
        sheet_id: str,
        **kwargs
    ) -> List[Dict]:
        """获取所有记录（自动分页）。"""
        all_records = []
        offset = 0
        limit = kwargs.pop("limit", 1000)

        while True:
            result = self.get_records(
                docid=docid,
                sheet_id=sheet_id,
                offset=offset,
                limit=limit,
                **kwargs
            )

            records = result.get("records", [])
            all_records.extend(records)

            if not result.get("has_more", False):
                break

            offset = result.get("next", offset + limit)

        return all_records
