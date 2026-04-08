import os
from urllib.parse import parse_qsl, quote_plus, urlencode, urlsplit, urlunsplit

from dotenv import load_dotenv

load_dotenv()


def _is_truthy(value):
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def _normalize_url(url):
    if url.startswith("postgres://"):
        return url.replace("postgres://", "postgresql://", 1)
    return url


def _add_sslmode(url):
    sslmode = os.getenv("DATABASE_SSLMODE", "").strip()
    if not sslmode and not _is_truthy(os.getenv("DATABASE_REQUIRE_SSL")):
        return url

    sslmode = sslmode or "require"
    parts = urlsplit(url)
    query = dict(parse_qsl(parts.query, keep_blank_values=True))
    query["sslmode"] = sslmode
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), parts.fragment))


def build_database_url():
    database_url = os.getenv("DATABASE_URL", "").strip()
    if database_url:
        return _add_sslmode(_normalize_url(database_url))

    host = os.getenv("DATABASE_HOST", "").strip()
    port = os.getenv("DATABASE_PORT", "5432").strip() or "5432"
    database_name = os.getenv("DATABASE_NAME", "").strip()
    username = os.getenv("DATABASE_USER", "").strip()
    password = os.getenv("DATABASE_PASSWORD", "")

    if not all([host, database_name, username, password]):
        raise RuntimeError(
            "Set DATABASE_URL or DATABASE_HOST/DATABASE_PORT/DATABASE_NAME/DATABASE_USER/DATABASE_PASSWORD."
        )

    composed_url = (
        f"postgresql://{quote_plus(username)}:{quote_plus(password)}"
        f"@{host}:{port}/{database_name}"
    )
    return _add_sslmode(composed_url)
