import os
import yaml

VEXA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vexa")
COMPOSE_FILE = os.path.join(VEXA_DIR, "deploy", "compose", "docker-compose.yml")

def clean_compose():
    if not os.path.exists(COMPOSE_FILE):
        print(f"Compose file not found: {COMPOSE_FILE}")
        return

    with open(COMPOSE_FILE, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)

    services_to_remove = ["agent-api", "terminal", "dashboard", "minio", "minio-init", "mcp"]
    services = data.get("services", {})

    for srv in services_to_remove:
        if srv in services:
            print(f"Removing service {srv} from docker-compose.yml")
            del services[srv]

    for srv_name, srv_def in services.items():
        depends_on = srv_def.get("depends_on", {})
        if isinstance(depends_on, dict):
            for target in services_to_remove:
                if target in depends_on:
                    print(f"Removing {target} from {srv_name} depends_on")
                    del depends_on[target]
        elif isinstance(depends_on, list):
            srv_def["depends_on"] = [dep for dep in depends_on if dep not in services_to_remove]

    with open(COMPOSE_FILE, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, sort_keys=False)
    print("Vexa docker-compose.yml cleaned up successfully.")

if __name__ == "__main__":
    try:
        import yaml
    except ImportError:
        import sys
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml"])
        import yaml
    clean_compose()
