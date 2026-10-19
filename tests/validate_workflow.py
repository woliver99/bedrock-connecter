#!/usr/bin/env python3
"""
Validates .github/workflows/publish-container-image.yml and Dockerfile.
"""
import os
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_PATH = os.path.join(ROOT_DIR, ".github", "workflows", "publish-container-image.yml")
DOCKERFILE_PATH = os.path.join(ROOT_DIR, "Dockerfile")

def validate():
    print("Validating GitHub Actions Workflow & Dockerfile...")

    # 1. Validate Workflow YAML
    if not os.path.exists(WORKFLOW_PATH):
        print("FAIL: Workflow file does not exist!")
        return 1

    try:
        # Check basic YAML loading if pyyaml is installed, or python parser
        import urllib.request
        with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
            content = f.read()

        # Check critical workflow sections
        required_elements = [
            "name:",
            "workflow_dispatch:",
            "mark_as_latest:",
            "version_tag:",
            "build-and-publish:",
            "ghcr.io",
            "docker/metadata-action",
            "docker/build-push-action",
            "softprops/action-gh-release",
            "egg-bedrockconnect-xboxbroadcast.json",
            "make_latest: ${{ inputs.mark_as_latest }}"
        ]
        for elem in required_elements:
            if elem not in content:
                print(f"FAIL: Workflow missing expected element: '{elem}'")
                return 1

        print("Workflow YAML structure: OK")
    except Exception as e:
        print(f"FAIL: Workflow validation error: {e}")
        return 1

    # 2. Validate Dockerfile
    if not os.path.exists(DOCKERFILE_PATH):
        print("FAIL: Dockerfile does not exist!")
        return 1

    with open(DOCKERFILE_PATH, "r", encoding="utf-8") as f:
        df_content = f.read()

    df_required = [
        "FROM eclipse-temurin:21-jre",
        "curl",
        "unzip",
        "useradd -d /home/container",
        "COPY --chmod=755 scripts/start.sh /usr/local/bin/start.sh",
        "COPY --chmod=755 scripts/entrypoint.sh /entrypoint.sh",
        "EXPOSE 19132/udp",
        "ENTRYPOINT [\"/entrypoint.sh\"]"
    ]
    for df_elem in df_required:
        if df_elem not in df_content:
            print(f"FAIL: Dockerfile missing element: '{df_elem}'")
            return 1

    print("Dockerfile structure: OK")
    print("SUCCESS: All workflow and Dockerfile checks passed!")
    return 0

if __name__ == "__main__":
    sys.exit(validate())
