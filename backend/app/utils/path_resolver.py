from typing import Optional, List, Dict, Tuple


def resolve_path(plex_path: str, path_mappings: List[Dict[str, str]]) -> Optional[str]:
    """Apply longest-prefix-first substitution to translate a Plex path to a worker path.

    Returns the resolved path, or None if no mapping matches.
    """
    if not path_mappings:
        return None

    # Sort by source_prefix length descending (longest match first)
    sorted_mappings = sorted(
        path_mappings,
        key=lambda m: len(m.get("source_prefix", "")),
        reverse=True,
    )

    for mapping in sorted_mappings:
        source = mapping.get("source_prefix", "")
        target = mapping.get("target_prefix", "")
        if source and plex_path.startswith(source):
            return target + plex_path[len(source):]

    return None


def determine_transfer_mode(
    plex_path: str,
    worker_is_local: bool,
    path_mappings: List[Dict[str, str]],
    plex_server_has_ssh: bool = False,
) -> Tuple[str, Optional[str]]:
    """Determine how a worker should access the source file.

    Returns (mode, resolved_input_path) where mode is one of:
    - "local": file exists at plex_path on this machine (local worker, no mapping needed)
    - "mapped": plex_path was translated via path_mappings
    - "ssh_pull": local worker + no mapping + plex server has SSH — pull file from NAS
    - "ssh_transfer": no mapping matched and worker is remote — needs SCP transfer
    """
    # Try path mapping first
    resolved = resolve_path(plex_path, path_mappings or [])
    if resolved:
        return ("mapped", resolved)

    if worker_is_local:
        if plex_server_has_ssh:
            # Local worker can't access the file directly, but can pull via SSH from the NAS
            return ("ssh_pull", None)
        # Local worker uses the plex path directly (or it'll fail at runtime if not mounted)
        return ("local", plex_path)

    # Remote worker with no mapping — needs file transfer
    return ("ssh_transfer", None)
