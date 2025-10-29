# Clap Messenger - Matrix Homeserver

Clap Messenger's backend server, based on [Matrix Synapse](https://github.com/matrix-org/synapse) v1.98.0.

## Overview

Clap Messenger is a secure, decentralized messaging platform built on the Matrix protocol. This repository contains the homeserver implementation powering the Clap ecosystem.

### Features

- ✅ **Decentralized**: Built on Matrix protocol with federation support
- ✅ **Secure**: End-to-end encryption for messages
- ✅ **Scalable**: Deployed on AWS ECS Fargate with auto-scaling
- ✅ **Open Registration**: Public sign-up enabled
- ✅ **Media Storage**: S3-backed media storage with CloudFront CDN
- ✅ **Production-Ready**: PostgreSQL database, monitoring, and logging

## Architecture

```
┌─────────────────┐
│   Client Apps   │
│  (Web/Android/  │
│      iOS)       │
└────────┬────────┘
         │
         │ HTTPS
         ↓
┌─────────────────┐
│   AWS ALB       │
│  (Load Balancer)│
└────────┬────────┘
         │
         ↓
┌─────────────────┐      ┌──────────────┐
│  ECS Fargate    │─────→│ RDS Postgres │
│  (Synapse)      │      │  (Database)  │
└────────┬────────┘      └──────────────┘
         │
         ↓
┌─────────────────┐      ┌──────────────┐
│      S3         │─────→│  CloudFront  │
│ (Media Storage) │      │    (CDN)     │
└─────────────────┘      └──────────────┘
```

## Quick Start (Local Development)

### Prerequisites

- Docker & Docker Compose
- PostgreSQL 14+ (or use Docker)

### 1. Clone Repository

```bash
git clone https://github.com/Clap-HQ/clap-synapse.git
cd clap-synapse
git checkout clap-stable
```

### 2. Generate Configuration

```bash
docker run -it --rm \
  -v $(pwd)/data:/data \
  -e SYNAPSE_SERVER_NAME=localhost \
  -e SYNAPSE_REPORT_STATS=no \
  matrixdotorg/synapse:latest generate
```

### 3. Run with Docker Compose

```bash
# Create docker-compose.yml (see docker/ directory)
docker-compose up -d
```

### 4. Create Admin User

```bash
docker exec -it clap-synapse register_new_matrix_user \
  http://localhost:8008 \
  -c /data/homeserver.yaml \
  -u admin \
  -p <password> \
  --admin
```

## Production Deployment (AWS)

See [AWS Deployment Guide](./aws/DEPLOYMENT_GUIDE.md) for complete instructions.

### Deployment Summary

1. **Network**: VPC with public/private subnets
2. **Database**: RDS PostgreSQL in private subnet
3. **Storage**: S3 + CloudFront for media
4. **Compute**: ECS Fargate with auto-scaling
5. **Load Balancer**: ALB with SSL termination
6. **DNS**: `matrix.clap.ac` with SRV records

### Environment Variables

See [env-template.txt](./aws/env-template.txt) for required variables.

Key variables:
- `SYNAPSE_SERVER_NAME=clap.ac`
- `POSTGRES_HOST=<RDS_ENDPOINT>`
- `S3_BUCKET_NAME=clap-messenger-media-*`
- `REGISTRATION_SHARED_SECRET=<GENERATE>`
- `MACAROON_SECRET_KEY=<GENERATE>`

## Configuration

### Main Config File

[`docker/conf/clap-homeserver.yaml`](./docker/conf/clap-homeserver.yaml)

Key customizations for Clap:
- Server name: `clap.ac`
- Public registration: Enabled
- Federation: Enabled
- S3 media storage
- PostgreSQL database
- Behind ALB (x_forwarded: true)

### Secrets Generation

```bash
# Generate secure secrets
openssl rand -base64 32  # Registration secret
openssl rand -base64 32  # Macaroon secret
openssl rand -base64 32  # Form secret
```

Store secrets in AWS Secrets Manager for production.

## CI/CD

Automated deployment via GitHub Actions:

```
Push to main → Build Docker image → Push to ECR → Update ECS Service
```

See [`.github/workflows/deploy.yml`](./.github/workflows/deploy.yml) (coming soon)

## Monitoring

- **Logs**: CloudWatch Logs (`/ecs/clap-synapse`)
- **Metrics**: CloudWatch metrics for ECS, ALB, RDS
- **Alerts**: Configured for high CPU, 5xx errors, DB connections
- **Dashboard**: CloudWatch dashboard for all services

## Federation

Clap Messenger federates with other Matrix servers.

**Test Federation:**
- Visit: https://federationtester.matrix.org
- Enter: `clap.ac`

**SRV Record:**
```
_matrix._tcp.clap.ac  SRV  10 0 8448 matrix.clap.ac.
```

## API Endpoints

- Client API: `https://matrix.clap.ac/_matrix/client/*`
- Server API: `https://matrix.clap.ac/_matrix/federation/*`
- Health Check: `https://matrix.clap.ac/health`
- Version: `https://matrix.clap.ac/_matrix/client/versions`

## Security

- ✅ TLS 1.2+ only
- ✅ Secrets stored in AWS Secrets Manager
- ✅ Private subnets for compute and database
- ✅ Security groups with least privilege
- ✅ S3 encryption at rest
- ✅ RDS encryption enabled
- ✅ Regular security updates

## Performance

**Current Setup:**
- Fargate: 0.5 vCPU, 1GB RAM
- RDS: db.t4g.micro
- Auto-scaling: 1-4 tasks based on CPU

**Expected Capacity:**
- ~500-1000 concurrent users
- ~100 messages/second
- Scales automatically with traffic

## Cost

**Monthly AWS Costs (Estimated):**
- Fargate: ~$15
- RDS: ~$15
- ALB: ~$20
- NAT Gateway: ~$32
- S3 + CloudFront: ~$5-10
- **Total: ~$88-98/month**

## Troubleshooting

### Can't connect to server
1. Check DNS resolution: `dig matrix.clap.ac`
2. Test HTTPS: `curl https://matrix.clap.ac/_matrix/client/versions`
3. Check ALB target health in AWS Console

### Federation not working
1. Verify SRV record: `dig SRV _matrix._tcp.clap.ac`
2. Test with: https://federationtester.matrix.org
3. Ensure port 8448 is accessible

### Database connection errors
1. Check RDS security group
2. Verify credentials in Secrets Manager
3. Check CloudWatch logs: `/ecs/clap-synapse`

## Development

### Local Changes

```bash
# Make changes to configuration
vim docker/conf/clap-homeserver.yaml

# Rebuild Docker image
docker build -t clap-synapse:dev -f docker/Dockerfile .

# Test locally
docker run --rm -p 8008:8008 clap-synapse:dev
```

### Testing

```bash
# Run tests
docker run --rm clap-synapse:dev python -m pytest
```

## Related Repositories

- **Web Client**: `Clap-HQ/clap-web` (coming soon)
- **Android Client**: `Clap-HQ/clap-x-android` (coming soon)
- **iOS Client**: `Clap-HQ/clap-x-ios` (coming soon)

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## License

Based on Matrix Synapse, licensed under Apache License 2.0.

See [LICENSE](./LICENSE) for details.

## Support

- **Issues**: https://github.com/Clap-HQ/clap-synapse/issues
- **Matrix Room**: `#clap:clap.ac` (coming soon)
- **Email**: support@clap.ac

## Acknowledgments

- Built on [Matrix Synapse](https://github.com/matrix-org/synapse)
- Powered by the [Matrix Protocol](https://matrix.org)
- Thanks to the Matrix.org Foundation and community

---

**Clap HQ** | Making messaging better 👏
