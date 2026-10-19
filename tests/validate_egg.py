#!/usr/bin/env python3
"""
Validation script for egg-bedrockconnect-xboxbroadcast.json.
Checks JSON schema, PTDL_v2 compliance, variable definitions, and shell syntax of embedded scripts.
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EGG_PATH = os.path.join(ROOT_DIR, "egg-bedrockconnect-xboxbroadcast.json")

def validate():
    print("Validating Pterodactyl Egg:", EGG_PATH)
    if not os.path.exists(EGG_PATH):
        print("FAIL: Egg file does not exist!")
        return 1

    try:
        with open(EGG_PATH, "r", encoding="utf-8") as f:
            egg = json.load(f)
    except Exception as e:
        print(f"FAIL: Invalid JSON format: {e}")
        return 1

    # Check top-level required fields
    required_keys = [
        "meta", "name", "author", "description",
        "docker_images", "startup", "config", "scripts", "variables"
    ]
    for key in required_keys:
        if key not in egg:
            print(f"FAIL: Missing required key '{key}'")
            return 1

    # Validate meta
    meta = egg.get("meta", {})
    if meta.get("version") != "PTDL_v2":
        print(f"FAIL: Expected meta.version to be 'PTDL_v2', got '{meta.get('version')}'")
        return 1

    # Validate docker images
    docker_images = egg.get("docker_images", {})
    if not isinstance(docker_images, dict) or len(docker_images) == 0:
        print("FAIL: docker_images must be a non-empty dictionary mapping names to image tags")
        return 1

    # Validate startup and config
    if not egg.get("startup"):
        print("FAIL: startup command is missing or empty")
        return 1

    config = egg.get("config", {})
    for c_key in ["files", "startup", "logs", "stop"]:
        if c_key not in config:
            print(f"FAIL: config is missing '{c_key}'")
            return 1

    # Validate variables
    variables = egg.get("variables", [])
    if not isinstance(variables, list) or len(variables) == 0:
        print("FAIL: variables list is empty")
        return 1

    var_req_keys = [
        "name", "description", "env_variable", "default_value",
        "user_viewable", "user_editable", "rules", "field_type"
    ]
    env_vars = set()
    for v in variables:
        for vk in var_req_keys:
            if vk not in v:
                print(f"FAIL: Variable '{v.get('name', 'UNKNOWN')}' is missing key '{vk}'")
                return 1
        env_vars.add(v["env_variable"])

    expected_vars = {
        "UPDATE_CHECK_INTERVAL",
        "AUTO_UPDATE_RESTART",
        "GITHUB_TOKEN",
        "JAVA_MEMORY_BC",
        "JAVA_MEMORY_XBL"
    }
    if not expected_vars.issubset(env_vars):
        print(f"FAIL: Missing expected environment variables: {expected_vars - env_vars}")
        return 1

    # Validate installation script syntax
    install_script = egg.get("scripts", {}).get("installation", {}).get("script", "")
    if not install_script:
        print("FAIL: installation script is missing or empty")
        return 1

    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as tmp_sh:
        tmp_sh.write(install_script)
        tmp_sh_path = tmp_sh.name

    try:
        proc = subprocess.run(["bash", "-n", tmp_sh_path], capture_output=True, text=True)
        if proc.returncode != 0:
            print(f"FAIL: Embedded installation script syntax error:\n{proc.stderr}")
            return 1
    finally:
        os.remove(tmp_sh_path)

    # Validate standalone start.sh
    start_sh = os.path.join(ROOT_DIR, "scripts", "start.sh")
    if os.path.exists(start_sh):
        proc = subprocess.run(["bash", "-n", start_sh], capture_output=True, text=True)
        if proc.returncode != 0:
            print(f"FAIL: scripts/start.sh syntax error:\n{proc.stderr}")
            return 1

    print("SUCCESS: All egg validations passed cleanly!")
    return 0

if __name__ == "__main__":
    sys.exit(validate())
