"""
TAX AI - MST Lookup Module
Tra cứu Mã Số Thuế từ VietQR API và masothue.com
"""
import re
import time
import logging
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from typing import Optional
from functools import lru_cache

import requests
from bs4 import BeautifulSoup

from config import (
    VIETQR_API_BASE,
    MASOTHUE_BASE,
    SCRAPER_TIMEOUT,
    SCRAPER_HEADERS,
    MAX_SEARCH_RESULTS,
    BING_SEARCH_KEY,
    GOOGLE_SEARCH_KEY,
    GOOGLE_SEARCH_CX,
)

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Data model
# ─────────────────────────────────────────────

@dataclass
class PersonalTaxInfo:
    cccd: str
    mst: str = ""
    full_name: str = ""
    address: str = ""
    status: str = ""
    error: str = ""

    def to_message(self) -> str:
        if self.error:
            return f"🪪 {self.error}"
        lines = [f"👤 *{self.full_name}*" if self.full_name else "👤 *Cá nhân*"]
        if self.mst:
            lines.append(f"🔢 MST cá nhân: `{self.mst}`")
        if self.status:
            if "đang hoạt động" in self.status.lower():
                lines.append(f"✅ Trạng thái: {self.status}")
            else:
                lines.append(f"[[R]]❌ Trạng thái: {self.status}[[/R]]")
                lines.append(f"[[R]]⚠️ CẦN LƯU Ý: NNT không đang hoạt động[[/R]]")
        if self.address:
            lines.append(f"📍 Địa chỉ: {self.address}")
        lines.append(f"🪪 CCCD: `{self.cccd}`")
        lines.append("📋 Nguồn: Tổng cục Thuế (GDT)")
        return "\n".join(lines)


@dataclass
class BusinessInfo:
    mst: str
    name: str = ""
    international_name: str = ""
    short_name: str = ""
    address: str = ""
    status: str = ""
    representative: str = ""
    business_type: str = ""
    active_date: str = ""
    phone: str = ""
    tax_department: str = ""
    source: str = ""
    error: str = ""

    @property
    def is_active(self) -> bool:
        return "đang hoạt động" in self.status.lower()

    def format_status_emoji(self) -> str:
        return "✅" if self.is_active else "❌"

    def to_message(self) -> str:
        if self.error:
            return f"❌ {self.error}"

        lines = [f"🏢 *{self.name}*"]
        if self.short_name and self.short_name != self.name:
            lines.append(f"📌 Tên ngắn: {self.short_name}")
        if self.international_name:
            lines.append(f"🌐 Tên quốc tế: {self.international_name}")
        lines.append(f"🔢 MST: `{self.mst}`")
        if self.is_active:
            lines.append(f"✅ Trạng thái: {self.status}")
        else:
            lines.append(f"[[R]]❌ Trạng thái: {self.status}[[/R]]")
            lines.append(f"[[R]]⚠️ CẦN LƯU Ý: NNT không đang hoạt động[[/R]]")
        lines.append(f"📍 Địa chỉ: {self.address}")
        if self.tax_department:
            lines.append(f"🏛 Cơ quan thuế: {self.tax_department}")
        if self.representative:
            lines.append(f"👤 Người đại diện: {self.representative}")
        if self.business_type:
            lines.append(f"🏭 Loại hình: {self.business_type}")
        if self.active_date:
            lines.append(f"📅 Ngày hoạt động: {self.active_date}")
        if self.phone:
            lines.append(f"📞 Điện thoại: {self.phone}")

        return "\n".join(lines)


# ─────────────────────────────────────────────
# Validators
# ─────────────────────────────────────────────

MST_PATTERN  = re.compile(r"^\d{10}(-\d{3})?$")
CCCD_PATTERN = re.compile(r"^\d{12}$")

def is_valid_mst(mst: str) -> bool:
    """MST doanh nghiệp: 10 hoặc 13 chữ số."""
    return bool(MST_PATTERN.match(mst.strip()))

def is_valid_cccd(text: str) -> bool:
    """CCCD / MST cá nhân: đúng 12 chữ số."""
    return bool(CCCD_PATTERN.match(text.strip()))


# ─────────────────────────────────────────────
# xinvoice.vn API (primary - by MST)
# ─────────────────────────────────────────────

XINVOICE_API_BASE = "https://api.xinvoice.vn/gdt-api"

def lookup_by_mst_xinvoice(mst: str) -> BusinessInfo:
    """Tra cứu MST qua xinvoice.vn /tax-payer — object đơn, đầy đủ cơ quan thuế."""
    url = f"{XINVOICE_API_BASE}/tax-payer/{mst.strip()}"
    try:
        for _attempt in range(3):
            resp = requests.get(url, timeout=SCRAPER_TIMEOUT, headers=SCRAPER_HEADERS)
            if resp.status_code == 429:
                time.sleep(1.5 * (_attempt + 1))
                continue
            break
        if resp.status_code == 404:
            return BusinessInfo(mst=mst, error="not_found")
        resp.raise_for_status()
        biz = resp.json()

        if not biz.get("taxID") and not biz.get("name"):
            return BusinessInfo(mst=mst, error="not_found")

        return BusinessInfo(
            mst=biz.get("taxID", mst),
            name=biz.get("name", ""),
            address=biz.get("address", ""),
            status=biz.get("status", ""),
            business_type=biz.get("orgType", ""),
            tax_department=biz.get("taxDepartment", ""),
            source="xinvoice.vn / GDT",
        )

    except requests.RequestException as e:
        logger.error("xinvoice API error: %s", e)
        return BusinessInfo(mst=mst, error="not_found")
    except (KeyError, ValueError) as e:
        logger.error("xinvoice parse error: %s", e)
        return BusinessInfo(mst=mst, error="not_found")


def get_branches_xinvoice(mst: str) -> list[BusinessInfo]:
    """Lấy danh sách chi nhánh qua xinvoice.vn /tax-payer-records."""
    url = f"{XINVOICE_API_BASE}/tax-payer-records/{mst.strip()}"
    try:
        resp = requests.get(url, timeout=SCRAPER_TIMEOUT, headers=SCRAPER_HEADERS)
        resp.raise_for_status()
        data = resp.json()
        if not data.get("success") or not data.get("data"):
            return []
        branches = []
        for biz in data["data"][1:]:  # bỏ qua index 0 (công ty mẹ)
            branches.append(BusinessInfo(
                mst=biz.get("taxID", ""),
                name=biz.get("name", ""),
                address=biz.get("address", ""),
                status=biz.get("status", ""),
                business_type=biz.get("orgType", ""),
                tax_department=biz.get("taxDepartment", ""),
                source="xinvoice.vn / GDT",
            ))
        return branches
    except Exception as e:
        logger.warning("get_branches_xinvoice error: %s", e)
        return []


# ─────────────────────────────────────────────
# VietQR API lookup (bổ sung international name)
# ─────────────────────────────────────────────

def lookup_by_mst_vietqr(mst: str) -> BusinessInfo:
    """Tra cứu MST qua VietQR API — có tên quốc tế và tên ngắn."""
    url = f"{VIETQR_API_BASE}/business/{mst.strip()}"
    try:
        resp = requests.get(url, timeout=SCRAPER_TIMEOUT, headers=SCRAPER_HEADERS)
        resp.raise_for_status()
        data = resp.json()

        if data.get("code") != "00":
            return BusinessInfo(mst=mst, error="not_found")

        biz = data["data"]
        return BusinessInfo(
            mst=biz.get("id", mst),
            name=biz.get("name", ""),
            international_name=biz.get("internationalName", ""),
            short_name=biz.get("shortName", ""),
            address=biz.get("address", ""),
            status=biz.get("status", ""),
            source="VietQR / GDT",
        )

    except requests.RequestException as e:
        logger.error("VietQR API error: %s", e)
        return BusinessInfo(mst=mst, error="not_found")
    except (KeyError, ValueError) as e:
        logger.error("VietQR parse error: %s", e)
        return BusinessInfo(mst=mst, error="not_found")


# ─────────────────────────────────────────────
# masothue.com scraper (fallback + name search)
# ─────────────────────────────────────────────

def _get_masothue_session():
    """
    Trả về session đã warmup (có cookie từ homepage).
    Warmup cần thiết để bypass anti-bot redirect của masothue.com.
    """
    try:
        import cloudscraper
        session = cloudscraper.create_scraper(
            browser={"browser": "chrome", "platform": "windows", "mobile": False}
        )
    except ImportError:
        session = requests.Session()

    session.headers.update({
        **SCRAPER_HEADERS,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Encoding": "gzip, deflate, br",
        "Connection": "keep-alive",
        "Upgrade-Insecure-Requests": "1",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "same-origin",
        "Sec-Fetch-User": "?1",
    })

    # Warmup: visit homepage để lấy cookie trước khi search
    try:
        session.get("https://masothue.com/", timeout=8, allow_redirects=True)
        logger.debug("masothue.com warmup OK")
    except Exception as e:
        logger.debug("masothue.com warmup failed: %s", e)

    return session


def _parse_taxinfo_table(soup: BeautifulSoup, mst: str) -> Optional[BusinessInfo]:
    """Parse bảng thông tin doanh nghiệp từ HTML masothue.com."""
    table = soup.find("table", class_="table-taxinfo")
    if not table:
        # Fallback: tìm theo heading
        table = soup.find("table")
    if not table:
        return None

    info: dict = {"mst": mst, "source": "masothue.com"}
    for row in table.find_all("tr"):
        cells = row.find_all(["th", "td"])
        if len(cells) < 2:
            continue
        label = cells[0].get_text(strip=True).lower()
        value = cells[1].get_text(strip=True)

        if "tên doanh nghiệp" in label or "tên công ty" in label:
            info["name"] = value
        elif "tên nước ngoài" in label or "international" in label:
            info["international_name"] = value
        elif "tên viết tắt" in label or "short" in label:
            info["short_name"] = value
        elif "địa chỉ" in label:
            info["address"] = value
        elif "tình trạng" in label or "trạng thái" in label:
            info["status"] = value
        elif "người đại diện" in label:
            info["representative"] = value
        elif "loại hình" in label:
            info["business_type"] = value
        elif "ngày hoạt động" in label or "ngày cấp" in label:
            info["active_date"] = value
        elif "điện thoại" in label:
            info["phone"] = value
        elif "mã số thuế" in label:
            info["mst"] = value

    return BusinessInfo(**info) if info.get("name") else None


def lookup_by_mst_masothue(mst: str) -> BusinessInfo:
    """Tra cứu MST qua masothue.com scraper."""
    session = _get_masothue_session()
    url = f"{MASOTHUE_BASE}/{mst.strip()}"
    try:
        resp = session.get(url, timeout=SCRAPER_TIMEOUT)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")
        result = _parse_taxinfo_table(soup, mst)
        if result:
            return result
        return BusinessInfo(mst=mst, error="Không tìm thấy thông tin trên masothue.com")
    except requests.RequestException as e:
        logger.warning("masothue.com scrape failed: %s", e)
        return BusinessInfo(mst=mst, error=f"Không thể truy cập masothue.com: {e}")


def _extract_search_results(soup: BeautifulSoup) -> list[BusinessInfo]:
    """
    Parse kết quả tìm kiếm từ masothue.com.
    Thử nhiều chiến lược vì HTML có thể thay đổi.
    """
    results = []
    seen_mst = set()

    # ── Chiến lược 1: Tìm tất cả link có href chứa MST ──
    all_links = soup.find_all("a", href=True)
    for link in all_links:
        href = link.get("href", "")
        mst_match = re.search(r"[/=](\d{10}(?:-\d{3})?)(?:[/?-]|$)", href)
        if not mst_match:
            continue
        extracted_mst = mst_match.group(1)
        if extracted_mst in seen_mst:
            continue
        biz_name = link.get_text(strip=True)
        # Lọc tên hợp lệ: ít nhất 5 ký tự, có chữ cái
        if len(biz_name) < 5 or not re.search(r"[a-zA-ZÀ-ỹ]", biz_name):
            continue
        # Bỏ qua link điều hướng (Home, Tìm kiếm,...)
        nav_words = {"trang chủ", "home", "search", "tìm kiếm", "đăng nhập", "liên hệ"}
        if biz_name.lower() in nav_words:
            continue
        seen_mst.add(extracted_mst)
        results.append(BusinessInfo(mst=extracted_mst, name=biz_name, source="masothue.com"))
        if len(results) >= MAX_SEARCH_RESULTS:
            break

    if results:
        return results

    # ── Chiến lược 2: Tìm trong bảng — hàng nào có MST 10 số ──
    for table in soup.find_all("table"):
        for row in table.find_all("tr"):
            cells = row.find_all(["td", "th"])
            row_text = " ".join(c.get_text(strip=True) for c in cells)
            mst_match = re.search(r"\b(\d{10})\b", row_text)
            if not mst_match:
                continue
            extracted_mst = mst_match.group(1)
            if extracted_mst in seen_mst:
                continue
            # Tên DN thường là cell đầu hoặc cell có nhiều chữ nhất
            biz_name = ""
            for cell in cells:
                txt = cell.get_text(strip=True)
                if re.search(r"[a-zA-ZÀ-ỹ]{3,}", txt) and txt != extracted_mst:
                    if len(txt) > len(biz_name):
                        biz_name = txt
            if not biz_name:
                continue
            seen_mst.add(extracted_mst)
            results.append(BusinessInfo(mst=extracted_mst, name=biz_name, source="masothue.com"))
            if len(results) >= MAX_SEARCH_RESULTS:
                break

    if results:
        return results

    # ── Chiến lược 3: Trang redirect về detail (1 kết quả) ──
    single = _parse_taxinfo_table(soup, "")
    if single:
        return [single]

    return []


def search_by_name_masothue(name: str, page: int = 1) -> list[BusinessInfo]:
    """Tìm kiếm doanh nghiệp theo tên trên masothue.com."""
    session = _get_masothue_session()
    url = f"{MASOTHUE_BASE}/Search"
    params = {"q": name, "page": page}

    try:
        resp = session.get(url, params=params, timeout=SCRAPER_TIMEOUT, allow_redirects=True)
        resp.raise_for_status()

        # Detect redirect ve homepage (IP bi block)
        final_url = resp.url.rstrip("/")
        homepage = MASOTHUE_BASE.rstrip("/")
        if final_url == homepage or not resp.url.lower().endswith(("search", f"q={name.lower()}")):
            # Kiem tra them: neu HTML khong chua keyword tim kiem → homepage
            if name.lower() not in resp.text.lower()[:5000]:
                logger.warning("masothue.com: redirected to homepage (IP blocked), skip")
                return []

        # Cloudflare block
        if resp.status_code == 403 or "cloudflare" in resp.text.lower()[:500]:
            logger.warning("masothue.com: Cloudflare block")
            return []

        soup = BeautifulSoup(resp.text, "html.parser")
        results = _extract_search_results(soup)
        # Bat buoc: ten DN phai chua cum tu tim kiem
        results = [r for r in results if name.lower() in r.name.lower()]
        logger.info("masothue.com search '%s': %d results", name, len(results))
        return results

    except Exception as e:
        logger.warning("masothue.com search failed: %s", e)
        return []


# ─────────────────────────────────────────────
# Unified API
# ─────────────────────────────────────────────

def lookup_mst(mst: str) -> BusinessInfo:
    """
    Tra cứu MST theo thứ tự:
    1. xinvoice.vn — đầy đủ nhất (cơ quan thuế, loại hình)
    2. VietQR      — bổ sung tên quốc tế, tên ngắn
    3. masothue.com — fallback cuối
    """
    mst = mst.strip()
    if not is_valid_mst(mst):
        return BusinessInfo(
            mst=mst,
            error=f"MST '{mst}' không đúng định dạng. MST phải có 10 hoặc 13 chữ số.",
        )

    # 1. xinvoice.vn (primary)
    result = lookup_by_mst_xinvoice(mst)
    if result.name:
        # Bổ sung tên quốc tế + tên ngắn từ VietQR nếu có
        vietqr = lookup_by_mst_vietqr(mst)
        if vietqr.name and not result.error:
            result.international_name = vietqr.international_name
            result.short_name = vietqr.short_name
            result.source = "GDT / xinvoice.vn + VietQR"
        return result

    # 2. VietQR
    logger.info("xinvoice failed, try VietQR for MST: %s", mst)
    result = lookup_by_mst_vietqr(mst)
    if result.name:
        return result

    # 3. masothue.com scraper
    logger.info("Fallback to masothue.com for MST: %s", mst)
    result = lookup_by_mst_masothue(mst)
    if result.name:
        return result

    return BusinessInfo(
        mst=mst,
        error=f"Không tìm thấy thông tin cho MST {mst}. Vui lòng kiểm tra lại."
    )


def _name_similarity(a: str, b: str) -> float:
    """Độ tương đồng 0-1 giữa 2 tên DN (không phân biệt hoa thường)."""
    return SequenceMatcher(None, a.lower().strip(), b.lower().strip()).ratio()


def _make_scraper():
    """Tạo session với headers browser thực."""
    try:
        import cloudscraper
        s = cloudscraper.create_scraper(
            browser={"browser": "chrome", "platform": "windows", "mobile": False}
        )
    except ImportError:
        s = requests.Session()
    s.headers.update({
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/124.0.0.0 Safari/537.36"
        ),
        "Accept-Language": "vi-VN,vi;q=0.9,en;q=0.8",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Referer": "https://www.google.com/",
    })
    return s


def _extract_msts_from_html(html: str, keyword: str) -> set[str]:
    """
    Trích MST (10 số) từ HTML theo nhiều chiến lược:
    1. URL masothue.com/{10digits}-*  (href hoặc cite trong kết quả search)
    2. Bing/Google cite pattern: masothue.com › {10digits}-*
    3. Window ±400 ký tự quanh keyword (tin cậy)
    KHÔNG fallback lấy tất cả số 10 chữ số — quá nhiều rác.
    """
    found: set[str] = set()

    # 1. masothue.com URL slugs (href, cite, plain text)
    # Patterns: masothue.com/0302654173-... hoặc masothue.com/0302654173"
    url_pat = re.compile(r"masothue\.com/(\d{10})[^0-9]")
    for mst in url_pat.findall(html):
        found.add(mst)

    # 2. Bing cite breadcrumb: masothue.com › 0302654173 hoặc masothue.com &rsaquo; 0302654173
    cite_pat = re.compile(r"masothue\.com\s*(?:›|&rsaquo;|/)\s*(\d{10})")
    for mst in cite_pat.findall(html):
        found.add(mst)

    # 3. Window ±400 ký tự quanh keyword (chỉ lấy 10-số)
    mst_pat = re.compile(r"\b(\d{10})\b")
    kw = keyword.lower()
    html_lower = html.lower()
    idx = 0
    while True:
        pos = html_lower.find(kw, idx)
        if pos == -1:
            break
        window = html[max(0, pos - 400): pos + 400]
        for mst in mst_pat.findall(window):
            found.add(mst)
        idx = pos + 1

    return found


def _search_xinvoice_by_name(name: str) -> list[BusinessInfo]:
    """
    Thử các endpoint search của xinvoice.vn (nếu tồn tại).
    Trả về list rỗng nếu không có endpoint nào hoạt động.
    """
    import urllib.parse
    encoded = urllib.parse.quote(name)
    candidates = [
        f"{XINVOICE_API_BASE}/tax-payer?name={encoded}",
        f"{XINVOICE_API_BASE}/tax-payer/search?keyword={encoded}",
        f"{XINVOICE_API_BASE}/tax-payers?name={encoded}",
        f"{XINVOICE_API_BASE}/search?q={encoded}",
    ]
    for url in candidates:
        try:
            r = requests.get(url, timeout=8, headers=SCRAPER_HEADERS)
            if r.status_code not in (200, 404):
                continue
            data = r.json()
            if not data or isinstance(data, dict) and data.get("error"):
                continue
            items = data if isinstance(data, list) else data.get("data", data.get("results", []))
            if not isinstance(items, list) or not items:
                continue
            results = []
            for item in items[:10]:
                mst = item.get("taxID") or item.get("mst") or item.get("taxCode", "")
                n   = item.get("name", "")
                if mst and name.lower() in n.lower():
                    results.append(BusinessInfo(
                        mst=mst, name=n,
                        address=item.get("address", ""),
                        status=item.get("status", ""),
                        business_type=item.get("orgType", ""),
                        source="xinvoice.vn search",
                    ))
            if results:
                logger.info("xinvoice name search '%s': %d results via %s", name, len(results), url)
                return results
        except Exception:
            pass
    return []


def _extract_msts_from_urls(urls: list[str]) -> set[str]:
    """Trích MST 10 số từ danh sách URL masothue.com."""
    found: set[str] = set()
    pat = re.compile(r"masothue\.com/(\d{10})")
    for url in urls:
        m = pat.search(url)
        if m:
            found.add(m.group(1))
    return found


def _search_by_bing_api(name: str) -> list[BusinessInfo]:
    """
    Dùng Bing Search API v7 (JSON) để tìm MST theo tên DN.
    Yêu cầu: env BING_SEARCH_KEY.
    Azure: Cognitive Services -> Bing Search v7, 1000 queries/month free.
    """
    if not BING_SEARCH_KEY:
        return []
    import urllib.parse
    query = f"{name} site:masothue.com"
    url = "https://api.bing.microsoft.com/v7.0/search"
    params = {"q": query, "count": "10", "mkt": "vi-VN"}
    headers = {"Ocp-Apim-Subscription-Key": BING_SEARCH_KEY}
    try:
        resp = requests.get(url, params=params, headers=headers, timeout=8)
        resp.raise_for_status()
        data = resp.json()
        pages = data.get("webPages", {}).get("value", [])
        urls = [p.get("url", "") for p in pages]
        mst_candidates = _extract_msts_from_urls(urls)
        logger.info("Bing API '%s': %d URLs, %d MST candidates", name, len(urls), len(mst_candidates))
    except Exception as e:
        logger.warning("Bing Search API error: %s", e)
        return []

    results = []
    for mst in list(mst_candidates)[:10]:
        info = lookup_by_mst_xinvoice(mst)
        if not info.name or info.error:
            continue
        if name.lower() not in info.name.lower():
            continue
        results.append((_name_similarity(name, info.name), info))

    results.sort(key=lambda x: x[0], reverse=True)
    return [r[1] for r in results[:6]]


def _search_by_google_cse(name: str) -> list[BusinessInfo]:
    """
    Dùng Google Custom Search JSON API để tìm MST theo tên DN.
    Yêu cầu: env GOOGLE_SEARCH_KEY + GOOGLE_SEARCH_CX.
    Setup: cse.google.com (tạo CSE targeting masothue.com) + Google Cloud (Custom Search JSON API key).
    100 queries/day free.
    """
    if not GOOGLE_SEARCH_KEY or not GOOGLE_SEARCH_CX:
        return []
    query = f"{name} site:masothue.com"
    url = "https://www.googleapis.com/customsearch/v1"
    params = {
        "key": GOOGLE_SEARCH_KEY,
        "cx": GOOGLE_SEARCH_CX,
        "q": query,
        "num": "10",
        "lr": "lang_vi",
    }
    try:
        resp = requests.get(url, params=params, timeout=8)
        resp.raise_for_status()
        data = resp.json()
        items = data.get("items", [])
        urls = [it.get("link", "") for it in items]
        mst_candidates = _extract_msts_from_urls(urls)
        logger.info("Google CSE '%s': %d items, %d MST candidates", name, len(items), len(mst_candidates))
    except Exception as e:
        logger.warning("Google CSE error: %s", e)
        return []

    results = []
    for mst in list(mst_candidates)[:10]:
        info = lookup_by_mst_xinvoice(mst)
        if not info.name or info.error:
            continue
        if name.lower() not in info.name.lower():
            continue
        results.append((_name_similarity(name, info.name), info))

    results.sort(key=lambda x: x[0], reverse=True)
    return [r[1] for r in results[:6]]

def _search_by_ddg(name: str) -> list[BusinessInfo]:
    """
    Dung DuckDuckGo HTML endpoint (html.duckduckgo.com/html/) de tim MST.
    DDG tra HTML that, accessible tu GreenNode voi headers dung.
    KEY: Accept: text/html (khong phai application/json).
    """
    import urllib.parse
    session = requests.Session()
    session.headers.update({
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
        "Accept-Language": "vi-VN,vi;q=0.9,en;q=0.8",
        "Referer": "https://duckduckgo.com/",
    })

    # Queries: site-restricted truoc, roi broad (no site:) de bat MST xuat hien tren nhieu nguon
    queries = [
        f"{name} site:masothue.com",
        f"{name} ma so thue",
        f"{name} mã số thuế công ty",
    ]

    url_pat = re.compile(r"masothue\.com/?(\d{10})")
    mst_pat = re.compile(r"\b(\d{10})\b")
    mst_candidates: set[str] = set()
    ddg_log: list[str] = []

    for query in queries:
        for ddg_url in [
            f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(query)}",
        ]:
            try:
                resp = session.get(ddg_url, timeout=10, allow_redirects=True)
                if resp.status_code != 200 or len(resp.text) < 3000:
                    ddg_log.append(f"q={query[:25]!r}: {resp.status_code} len={len(resp.text)}")
                    continue
                html = resp.text
                before = len(mst_candidates)
                # Chien luoc 1: URL masothue.com/MST (chinh xac nhat)
                for mst in url_pat.findall(html):
                    mst_candidates.add(mst)
                # Chien luoc 2: window +- 400 ky tu quanh ten cty trong page
                kw = name.lower()
                hl = html.lower()
                idx = 0
                while True:
                    pos = hl.find(kw, idx)
                    if pos == -1:
                        break
                    window = html[max(0, pos - 400): pos + 400]
                    for m in mst_pat.findall(window):
                        mst_candidates.add(m)
                    idx = pos + 1
                # Chien luoc 3 (broad query): moi so 10 chu so trong toan bo trang
                if "site:" not in query:
                    for m in mst_pat.findall(html):
                        mst_candidates.add(m)
                ddg_log.append(f"q={query[:30]!r} new={len(mst_candidates)-before}")
            except Exception as e:
                ddg_log.append(f"ERR {e!s:.50s}")

        if len(mst_candidates) >= 5:
            break

    logger.info("DDG search '%s': %s | total=%d", name, " | ".join(ddg_log), len(mst_candidates))

    if not mst_candidates:
        return []

    results = []
    for mst in list(mst_candidates)[:15]:
        info = lookup_by_mst_xinvoice(mst)
        if not info.name or info.error:
            continue
        if name.lower() not in info.name.lower():
            continue
        results.append((_name_similarity(name, info.name), info))

    results.sort(key=lambda x: x[0], reverse=True)
    logger.info("DDG '%s': %d verified results from %d candidates", name, len(results), len(mst_candidates))
    return [r[1] for r in results[:6]]


def _search_by_playwright(name: str) -> list[BusinessInfo]:
    """
    Mo Chromium headless, vao Google tim "{name} ma so thue",
    lay full page text, extract moi so 10 chu so, verify qua xinvoice.vn,
    giu lai ket qua co ten chua keyword tim kiem.
    Khong phu thuoc masothue.com.
    """
    try:
        from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout
    except ImportError:
        logger.warning("Playwright not installed")
        return []

    import urllib.parse
    mst_pat = re.compile(r"\b(\d{10})\b")
    mst_candidates: set[str] = set()
    pw_log: list[str] = []

    # Cac query Google theo do rong tang dan
    google_queries = [
        f'"{name}" "mã số thuế"',
        f"{name} mã số thuế",
        f"{name} ma so thue cong ty",
    ]

    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                headless=True,
                args=[
                    "--no-sandbox",
                    "--disable-setuid-sandbox",
                    "--disable-dev-shm-usage",
                    "--disable-gpu",
                    "--disable-extensions",
                    # Bypass bot detection
                    "--disable-blink-features=AutomationControlled",
                ],
            )
            ctx = browser.new_context(
                viewport={"width": 1366, "height": 768},
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/124.0.0.0 Safari/537.36"
                ),
                locale="vi-VN",
                java_script_enabled=True,
            )
            # Xoa dau hieu automation
            ctx.add_init_script(
                "Object.defineProperty(navigator, 'webdriver', {get: () => undefined})"
            )
            page = ctx.new_page()

            for query in google_queries:
                gurl = (
                    "https://www.google.com/search?q="
                    + urllib.parse.quote(query)
                    + "&hl=vi&gl=vn&num=10"
                )
                try:
                    page.goto(gurl, wait_until="networkidle", timeout=20000)
                except PWTimeout:
                    try:
                        page.wait_for_timeout(3000)
                    except Exception:
                        pass

                # Lay full text cua trang (sach hon HTML)
                try:
                    text = page.inner_text("body")
                except Exception:
                    text = page.content()

                html = page.content()
                html_len = len(html)

                # Extract tat ca so 10 chu so tu page text
                before = len(mst_candidates)
                all_msts = set(mst_pat.findall(text))
                # Uu tien: so 10 chu so xuat hien gan keyword
                kw = name.lower()
                txt_lower = text.lower()
                idx = 0
                near_kw: set[str] = set()
                while True:
                    pos = txt_lower.find(kw, idx)
                    if pos == -1:
                        break
                    window = text[max(0, pos - 300): pos + 300]
                    for m in mst_pat.findall(window):
                        near_kw.add(m)
                    idx = pos + 1

                # Them near-keyword truoc, roi full list
                mst_candidates.update(near_kw)
                mst_candidates.update(all_msts)

                pw_log.append(
                    f"google q={query[:35]!r}: html={html_len} "
                    f"near={len(near_kw)} all={len(all_msts)} total={len(mst_candidates)}"
                )

                if len(mst_candidates) >= 5:
                    break

            browser.close()

    except Exception as e:
        logger.warning("Playwright/Google search failed: %s", e)
        return []

    logger.info("Playwright '%s': %s", name, " | ".join(pw_log))

    if not mst_candidates:
        return []

    # Verify tung candidate qua xinvoice.vn
    # Bat buoc: ten DN tra ve phai chua keyword tim kiem
    verified: list[tuple[float, BusinessInfo]] = []
    for i, mst in enumerate(list(mst_candidates)[:30]):
        if i > 0:
            time.sleep(0.4)  # tranh rate limit xinvoice 429
        info = lookup_by_mst_xinvoice(mst)
        if not info.name or info.error:
            continue
        if name.lower() not in info.name.lower():
            continue
        sim = _name_similarity(name, info.name)
        verified.append((sim, info))
        if len(verified) >= 6:
            break

    verified.sort(key=lambda x: x[0], reverse=True)
    logger.info("Playwright '%s': %d verified from %d candidates", name, len(verified), len(mst_candidates))
    return [r[1] for r in verified[:6]]


def search_company_by_google(name: str) -> list[BusinessInfo]:
    """
    Tim DN theo ten. Thu tu:
    1. xinvoice.vn search API
    2. DuckDuckGo HTML (hoat dong tot tu GreenNode)
    3. Bing Search API v7 (neu co BING_SEARCH_KEY)
    4. Google CSE (neu co GOOGLE_SEARCH_KEY)
    5. Playwright Chromium (fallback nang)
    6. Bing HTML scraping (last resort)
    """
    import urllib.parse

    results = _search_xinvoice_by_name(name)
    if results:
        return results

    # Playwright: mo Google voi Chromium - hoat dong tot tu GreenNode
    results = _search_by_playwright(name)
    if results:
        return results

    # DDG HTML - backup (doi khi bi 202 anti-bot)
    results = _search_by_ddg(name)
    if results:
        return results

    results = _search_by_bing_api(name)
    if results:
        return results

    results = _search_by_google_cse(name)
    if results:
        return results

    # Last resort: Bing HTML (thuong that bai do JS render)
    session = _make_scraper()
    mst_candidates: set[str] = set()
    search_log: list[str] = []

    bing_queries = [
        f"{name} site:masothue.com",
        f"MST {name} site:masothue.com",
        f"{name} ma so thue",
    ]

    for query in bing_queries:
        url = (
            "https://www.bing.com/search"
            f"?q={urllib.parse.quote(query)}&cc=vn&setlang=vi&count=10"
        )
        try:
            resp = session.get(url, timeout=12)
            status = resp.status_code
            body_len = len(resp.text)
            msts: set[str] = set()
            if status == 200 and body_len > 1000:
                msts = _extract_msts_from_html(resp.text, name)
                mst_candidates.update(msts)
            search_log.append(
                f"Bing q='{query}' -> {status} len={body_len} msts={len(msts)} "
                f"masothue={resp.text.lower().count('masothue')}"
            )
            if len(mst_candidates) >= 3:
                break
        except Exception as e:
            search_log.append(f"Bing q='{query}' -> FAIL: {e}")

    logger.info("Bing HTML search '%s': %s", name, " | ".join(search_log))

    if not mst_candidates:
        logger.warning("Search: 0 MST candidates for '%s'. Engines may be blocked.", name)
        return []

    verified: list[tuple[float, BusinessInfo]] = []
    for mst in list(mst_candidates)[:20]:
        info = lookup_by_mst_xinvoice(mst)
        if not info.name or info.error:
            continue
        if name.lower() not in info.name.lower():
            continue
        sim = _name_similarity(name, info.name)
        verified.append((sim, info))

    verified.sort(key=lambda x: x[0], reverse=True)
    logger.info("Search '%s': %d verified results from %d candidates",
                name, len(verified), len(mst_candidates))
    return [r[1] for r in verified[:6]]


def search_company(name: str) -> list[BusinessInfo]:
    """Tim kiem doanh nghiep theo ten."""
    import urllib.parse
    name = name.strip()
    if not name:
        return []

    results = search_company_by_google(name)
    if results:
        return results

    results = search_by_name_masothue(name)
    if results:
        return results

    return [BusinessInfo(
        mst="",
        name=name,
        error=(
            f"Khong tim thay ket qua cho '{name}'."
            f"\n\nThu tim truc tiep:"
            f"\n https://masothue.com/Search?q=" + urllib.parse.quote(name)
        )
    )]


def lookup_by_cccd(cccd: str) -> PersonalTaxInfo:
    """Tra cuu MST ca nhan theo CCCD."""
    link = "https://tracuunnt.gdt.gov.vn/tcnnt/mstcn.jsp"
    return PersonalTaxInfo(
        cccd=cccd,
        error=(
            f"Tra cuu MST ca nhan theo CCCD {cccd}:\n"
            f"Truy cap: {link}\n"
            f"Nhap CCCD/CMND vao o tim kiem."
        )
    )
