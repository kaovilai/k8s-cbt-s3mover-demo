# Running Minikube in Devcontainer

## Current Status: Not Configured

The devcontainer currently **does not support** minikube out of the box.

## Requirements for Minikube

Minikube has several driver options, each with different requirements:

| Driver | Requirements | Works in Devcontainer? |
|--------|--------------|------------------------|
| **docker** | Docker socket access | ⚠️ Needs configuration |
| **podman** | Podman installed | ❌ Not installed |
| **none** | Root access, bare metal | ❌ Requires privileged mode |
| **kvm2** | Nested virtualization | ❌ Not available in containers |
| **virtualbox** | Nested virtualization | ❌ Not available in containers |

## Option 1: Enable Docker-in-Docker (Recommended)

### Update devcontainer.json

```json
{
  "name": "Claude Code Sandbox with Minikube",
  "build": {
    "dockerfile": "Dockerfile"
  },
  "runArgs": [
    "--cap-add=NET_ADMIN",
    "--cap-add=NET_RAW",
    "--cap-add=SYS_ADMIN",
    "--privileged",
    "--security-opt", "seccomp=unconfined"
  ],
  "mounts": [
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",
    "source=claude-code-bashhistory-${devcontainerId},target=/commandhistory,type=volume",
    "source=claude-code-config-${devcontainerId},target=/home/node/.claude,type=volume"
  ],
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {
      "version": "latest",
      "moby": true,
      "dockerDashComposeVersion": "v2"
    }
  }
}
```

### Update Dockerfile

```dockerfile
FROM node:20

# ... existing configuration ...

# Install Docker CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
  && apt-get update \
  && apt-get install -y docker-ce-cli \
  && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
  && rm kubectl

# Install minikube
RUN curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  && install minikube-linux-amd64 /usr/local/bin/minikube \
  && rm minikube-linux-amd64

# Add node user to docker group
RUN groupadd -f docker && usermod -aG docker node

# ... rest of existing configuration ...
```

### Usage

```bash
# Start minikube with docker driver
minikube start --driver=docker --container-runtime=containerd

# Deploy your demo
./scripts/01-deploy-csi-driver.sh

# Test block PVCs!
kubectl apply -f manifests/workload/postgres-block.yaml
```

## Option 2: Use Host Docker Socket (Simpler)

### Update only devcontainer.json

```json
{
  "runArgs": [
    "--cap-add=NET_ADMIN",
    "--cap-add=NET_RAW"
  ],
  "mounts": [
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",
    // ... other mounts
  ]
}
```

Then install Docker CLI and minikube in the postCreateCommand:

```json
{
  "postCreateCommand": "bash -c 'curl -fsSL https://get.docker.com | sh && curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube && sudo usermod -aG docker node'"
}
```

## Option 3: Use Kind Instead (Current Approach)

Keep the current configuration and use Kind for local testing:

**Pros:**
- ✅ Already working
- ✅ Lighter weight
- ✅ Faster startup
- ✅ Good for filesystem PVC testing

**Cons:**
- ❌ Block PVCs don't work reliably
- ❌ Can't run the full upstream integration tests

## Recommendation

**For this devcontainer:**

1. **Keep Kind for local development** (current approach)
   - Fast, works out of the box
   - Good for testing snapshot workflow
   - Filesystem PVCs work fine with PostgreSQL

2. **Use GitHub Actions with minikube** for full testing
   - Create `.github/workflows/integration-test-minikube.yaml`
   - Run the full upstream test suite
   - Test block PVCs and actual CBT metadata tools

3. **Use EKS/cloud for production testing**
   - Already configured in `demo-aws.yaml`
   - Real block device support
   - Full CBT functionality

## Security Considerations

Running Docker-in-Docker or mounting the Docker socket has security implications:

**Risks:**
- Container can manipulate host Docker daemon
- Essentially gives root access to the host
- Should only be used in trusted development environments

**Mitigations:**
- Only use in personal development environments
- Don't use in shared or production environments
- Consider using rootless Docker if possible

## Testing Matrix

Here's what works where:

| Feature | Current Devcontainer | + Docker-in-Docker | GitHub Actions + Minikube |
|---------|---------------------|--------------------|-----------------------------|
| Kind | ✅ | ✅ | ✅ |
| Minikube | ❌ | ✅ | ✅ |
| Block PVCs | ❌ | ✅ | ✅ |
| Filesystem PVCs | ✅ | ✅ | ✅ |
| CBT metadata tools | ⚠️ | ✅ | ✅ |
| Fast iteration | ✅ | ⚠️ | ❌ |

## Conclusion

**For this project, I recommend:**

1. **Don't modify the devcontainer** - Keep it simple and working
2. **Create a separate minikube integration test workflow** for CI
3. **Document the trade-offs clearly** (already done in `MINIKUBE_VS_KIND.md`)

This gives you:
- Fast local development with Kind
- Full testing with minikube in CI
- Production validation with EKS

Each tool serves a different purpose in the development workflow.
