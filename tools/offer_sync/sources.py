"""Where a shop's Facebook posts come from. One interface, two real sources, one for tests.

    GraphApiSource       the official Graph API with a page access token the page owner generated (no per-call cost)
    ScrapeCreatorsSource scrapecreators.com /v1/facebook/profile/posts (pre-purchased credits, 3 posts per page)
    FixtureSource        fixed posts, for tests and dry runs

Every source yields normalised posts: {post_id, url, text, posted_at, image_urls[]}. `fetch(url, headers) -> (status, bytes)`
is injectable so tests never touch the network. Secrets arrive as arguments; nothing here reads or writes a file.
"""
import ipaddress
import json
import socket
import urllib.error
import urllib.parse
import urllib.request

GRAPH = "https://graph.facebook.com/v21.0"
SCRAPECREATORS = "https://api.scrapecreators.com"
MAX_IMAGE_BYTES = 3 * 1024 * 1024
IMAGE_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}


class SourceError(Exception):
    """kind: reconnect (token or permission problem, a person must act), rate (try later), error (anything else)."""

    def __init__(self, kind, message):
        super().__init__(message)
        self.kind = kind


def http_fetch(url, headers=None, timeout=30):
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(MAX_IMAGE_BYTES + 1 if "image" in (r.headers.get("content-type") or "") else 5_000_000)
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:5000]
    except (urllib.error.URLError, TimeoutError) as e:
        raise SourceError("error", f"network error: {e}")


def _json(status, body, what):
    try:
        data = json.loads(body)
    except ValueError:
        raise SourceError("error", f"{what}: reply is not JSON (HTTP {status})")
    return data


def _post(post_id, url, text, posted_at, images):
    return {"post_id": str(post_id), "url": url or "", "text": text or "", "posted_at": posted_at or "",
            "image_urls": [u for u in dict.fromkeys(images) if isinstance(u, str) and u.startswith("https://")]}


class PostSource:
    calls = 0

    def recent(self, seen=(), max_pages=3):
        """Newest first. Stops at the first post whose id is in `seen`, or after `max_pages` pages."""
        raise NotImplementedError


class FixtureSource(PostSource):
    def __init__(self, posts):
        self.posts = posts

    def recent(self, seen=(), max_pages=3):
        out = []
        for p in self.posts:
            if p["post_id"] in seen:
                break
            out.append(p)
        return out


class GraphApiSource(PostSource):
    """GET /{page-id}/posts with a Page access token. Errors 190 (token) and 10/200 (permission) mean the page owner
    must reconnect; they are reported as SourceError('reconnect'), never a crash."""

    FIELDS = "id,message,created_time,permalink_url,full_picture,attachments{media,subattachments{media}}"

    def __init__(self, page_id, token, fetch=http_fetch, max_calls=5):
        self.page_id, self.token, self.fetch, self.max_calls, self.calls = page_id, token, fetch, max_calls, 0

    def _images(self, p):
        urls = [p.get("full_picture")]
        for a in (p.get("attachments") or {}).get("data", []):
            urls.append(((a.get("media") or {}).get("image") or {}).get("src"))
            for s in (a.get("subattachments") or {}).get("data", []):
                urls.append(((s.get("media") or {}).get("image") or {}).get("src"))
        return urls

    def recent(self, seen=(), max_pages=3):
        url = f"{GRAPH}/{urllib.parse.quote(str(self.page_id))}/posts?" + urllib.parse.urlencode(
            {"fields": self.FIELDS, "limit": 10, "access_token": self.token})
        out = []
        for _ in range(max_pages):
            if self.calls >= self.max_calls:
                break
            self.calls += 1
            status, body = self.fetch(url, {})
            data = _json(status, body, "Graph API")
            err = data.get("error")
            if err:
                code = err.get("code")
                if code in (190, 10, 200, 102, 104) or err.get("type") == "OAuthException":
                    raise SourceError("reconnect", "Facebook rejected the page token or permission; the page owner must reconnect the page")
                if code in (4, 17, 32, 613):
                    raise SourceError("rate", "Facebook rate limit; try again later")
                raise SourceError("error", f"Graph API error {code}")
            for p in data.get("data", []):
                if str(p.get("id")) in seen:
                    return out
                out.append(_post(p.get("id"), p.get("permalink_url"), p.get("message"), p.get("created_time"), self._images(p)))
            url = (data.get("paging") or {}).get("next")
            if not url:
                break
        return out


class ScrapeCreatorsSource(PostSource):
    """GET /v1/facebook/profile/posts?url=<page url>, header x-api-key, `cursor` to continue, 3 posts per page.
    The field names below are tolerant on purpose: the real response is recorded once (fixture) before they are trusted."""

    def __init__(self, page_url, api_key, fetch=http_fetch, max_calls=3):
        self.page_url, self.api_key, self.fetch, self.max_calls, self.calls = page_url, api_key, fetch, max_calls, 0

    @staticmethod
    def _first(d, *keys):
        for k in keys:
            if d.get(k):
                return d[k]
        return None

    def _normalise(self, p):
        imgs = []
        for k in ("image", "imageUrl", "image_url", "thumbnail", "full_picture"):
            v = p.get(k)
            imgs.append(v.get("uri") or v.get("url") if isinstance(v, dict) else v)
        for k in ("images", "photos", "attachments"):
            for v in p.get(k) or []:
                imgs.append((v.get("uri") or v.get("url") or v.get("src")) if isinstance(v, dict) else v)
        pid = self._first(p, "id", "postId", "post_id", "feedback_id")
        if not pid:
            return None
        return _post(pid, self._first(p, "url", "permalink", "permalink_url", "postUrl"),
                     self._first(p, "text", "message", "caption", "content"),
                     self._first(p, "publishTime", "publish_time", "created_time", "creation_time", "timestamp", "date"), imgs)

    def recent(self, seen=(), max_pages=3):
        out, cursor = [], None
        for _ in range(max_pages):
            if self.calls >= self.max_calls:
                break
            self.calls += 1
            q = {"url": self.page_url}
            if cursor:
                q["cursor"] = cursor
            status, body = self.fetch(f"{SCRAPECREATORS}/v1/facebook/profile/posts?" + urllib.parse.urlencode(q), {"x-api-key": self.api_key})
            if status in (401, 403):
                raise SourceError("reconnect", "ScrapeCreators rejected the API key")
            if status == 402:
                raise SourceError("reconnect", "ScrapeCreators credits are used up")
            if status == 429:
                raise SourceError("rate", "ScrapeCreators rate limit; try again later")
            data = _json(status, body, "ScrapeCreators")
            if status >= 400:
                raise SourceError("error", f"ScrapeCreators HTTP {status}")
            posts = data.get("posts") or data.get("data") or []
            for p in posts if isinstance(posts, list) else []:
                n = self._normalise(p) if isinstance(p, dict) else None
                if n is None:
                    continue
                if n["post_id"] in seen:
                    return out
                out.append(n)
            cursor = data.get("cursor") or data.get("next_cursor")
            if not cursor or not posts:
                break
        return out


def _public_host(host):
    """True when every address the host resolves to is public (no loopback, private, link-local, reserved)."""
    try:
        infos = socket.getaddrinfo(host, 443, proto=socket.IPPROTO_TCP)
    except OSError:
        return False
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast or ip.is_unspecified:
            return False
    return bool(infos)


def download_image(url, fetch=None, resolver=_public_host):
    """Fetch a post image now (Facebook CDN links expire). Returns (bytes, ext) or None. https only, public hosts only,
    at most 3 MB, and only a real jpeg, png or webp (judged by the bytes, not the header)."""
    p = urllib.parse.urlparse(url or "")
    if p.scheme != "https" or not p.hostname or p.username or p.port not in (None, 443):
        return None
    if not resolver(p.hostname):
        return None
    status, body = (fetch or http_fetch)(url, {})
    if status != 200 or not body or len(body) > MAX_IMAGE_BYTES:
        return None
    kind = (body[:3] == b"\xff\xd8\xff" and "jpg") or (body[:8] == b"\x89PNG\r\n\x1a\n" and "png") \
        or (body[:4] == b"RIFF" and body[8:12] == b"WEBP" and "webp")
    return (body, kind) if kind else None
