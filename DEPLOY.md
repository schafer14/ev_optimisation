# Deploy

## Deploying Optimiser on Cloud Run

```bash
cd mipaas
docker build -t mipaas:latest .
docker tag mipaas:latest australia-southeast1-docker.pkg.dev/mipaas/mipaas/mipaas:latest
docker push australia-southeast1-docker.pkg.dev/mipaas/mipaas/mipaas:latest
gcloud run deploy mipaas \
  --image australia-southeast1-docker.pkg.dev/PROJECT/mipaas/mipaas:latest \
  --port 8080 \
  --memory 4Gi \
  --cpu 2 \
  --region australia-southeast1
```
