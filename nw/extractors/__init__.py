"""Pluggable link extractors.

An extractor turns a share URL into a list of downloadable media items.
Two implementations ship here:

* ``DiskwalaExtractor`` - talks to the share host directly (no third party).
* ``ProviderExtractor``  - delegates to an extraction API you supply a key for.

Both expose the same ``inspect(url) -> LinkInfo`` interface so the rest of the
app does not care which one is active.
"""

from .base import ExtractorError, LinkInfo, MediaItem
from .diskwala import DiskwalaExtractor
from .api_provider import ProviderExtractor

__all__ = [
    "ExtractorError",
    "LinkInfo",
    "MediaItem",
    "DiskwalaExtractor",
    "ProviderExtractor",
    "get_extractor",
]


def get_extractor(config):
    """Pick an extractor based on config.

    If ``NW_API_URL`` is configured we delegate to that provider; otherwise we
    talk to the share host directly.
    """
    if config.api_url:
        return ProviderExtractor(config)
    return DiskwalaExtractor(config)
