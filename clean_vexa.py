import os
import sys
import re

VEXA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vexa")
COMPOSE_FILE = os.path.join(VEXA_DIR, "deploy", "compose", "docker-compose.yml")

SERVICES_TO_REMOVE = ["agent-api", "terminal", "dashboard", "minio", "minio-init", "mcp"]

def patch_minio_image_fallbacks():
    """Ensure any minio images use quay.io instead of deprecated Docker Hub."""
    if not os.path.exists(COMPOSE_FILE):
        return
    with open(COMPOSE_FILE, "r", encoding="utf-8") as f:
        content = f.read()
    content = content.replace("image: minio/minio:", "image: quay.io/minio/minio:")
    content = content.replace("image: minio/minio\n", "image: quay.io/minio/minio:latest\n")
    content = content.replace("image: minio/mc:", "image: quay.io/minio/mc:")
    content = content.replace("image: minio/mc\n", "image: quay.io/minio/mc:latest\n")
    with open(COMPOSE_FILE, "w", encoding="utf-8") as f:
        f.write(content)

def clean_with_yaml():
    import yaml
    if not os.path.exists(COMPOSE_FILE):
        print(f"Compose file not found: {COMPOSE_FILE}")
        return False

    with open(COMPOSE_FILE, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    if not isinstance(data, dict):
        return False

    services = data.get("services", {})
    for srv in SERVICES_TO_REMOVE:
        if srv in services:
            print(f"Removing unused service '{srv}' from docker-compose.yml")
            del services[srv]

    for srv_name, srv_def in services.items():
        if not isinstance(srv_def, dict):
            continue
        depends_on = srv_def.get("depends_on", {})
        if isinstance(depends_on, dict):
            for target in SERVICES_TO_REMOVE:
                if target in depends_on:
                    print(f"Removing '{target}' dependency from '{srv_name}'")
                    del depends_on[target]
        elif isinstance(depends_on, list):
            srv_def["depends_on"] = [dep for dep in depends_on if dep not in SERVICES_TO_REMOVE]

    with open(COMPOSE_FILE, "w", encoding="utf-8") as f:
        yaml.dump(data, f, sort_keys=False)

    patch_minio_image_fallbacks()
    print("Vexa docker-compose.yml cleaned up successfully (yaml parser).")
    return True

def clean_without_yaml():
    """Text-based fallback if PyYAML is not available."""
    if not os.path.exists(COMPOSE_FILE):
        print(f"Compose file not found: {COMPOSE_FILE}")
        return False

    with open(COMPOSE_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    output = []
    skipping = False
    for line in lines:
        match = re.match(r"^  ([a-zA-Z0-9_-]+):\s*$", line)
        if match:
            srv = match.group(1)
            if srv in SERVICES_TO_REMOVE:
                skipping = True
                print(f"Removing unused service '{srv}' from docker-compose.yml (regex fallback)")
                continue
            else:
                skipping = False
        elif skipping:
            if re.match(r"^(volumes:|networks:|  [a-zA-Z0-9_-]+:)", line):
                skipping = False
            else:
                continue

        # Drop dependency lines referencing removed services
        if any(f"{target}:" in line or f"- {target}" in line for target in SERVICES_TO_REMOVE):
            continue

        output.append(line)

    with open(COMPOSE_FILE, "w", encoding="utf-8") as f:
        f.writelines(output)

    patch_minio_image_fallbacks()
    print("Vexa docker-compose.yml cleaned up successfully (regex fallback).")
    return True

def clean_compose():
    try:
        import yaml
        clean_with_yaml()
        return
    except ImportError:
        pass

    # Try installing pyyaml safely
    installed = False
    for pip_cmd in [
        [sys.executable, "-m", "pip", "install", "pyyaml", "--break-system-packages"],
        [sys.executable, "-m", "pip", "install", "pyyaml"],
    ]:
        try:
            import subprocess
            subprocess.check_call(pip_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            import yaml
            installed = True
            break
        except Exception:
            continue

    if installed:
        clean_with_yaml()
    else:
        print("PyYAML not found; running resilient text-based cleaner fallback.")
        clean_without_yaml()

if __name__ == "__main__":
    clean_compose()
