# Railway Deployment Guide

## 🎯 Complete Step-by-Step Deployment

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/YLCYUz?referralCode=CGGc7W)

### Prerequisites
- GitHub account with this repository
- Railway account (free tier works)
- Basic understanding of environment variables

### Step 1: Prepare Repository

1. **Fork or clone this repository**
2. **Push to your GitHub account**
3. **Ensure all files are present**:
   - `Dockerfile`
   - `railway.json` 
   - `config/` directory with all files
   - `scripts/entrypoint.sh`

### Step 2: Create Railway Project

1. **Go to [Railway.app](https://railway.app)**
2. **Sign in with GitHub**
3. **Click "New Project"**
4. **Choose "Empty Project"**

### Step 3: Add Database Services

#### Add MySQL:
1. **Click "Add Service"**
2. **Select "Database"**
3. **Choose "MySQL"**
4. **Wait for deployment** (2-3 minutes)

#### Add Redis:
1. **Click "Add Service"** again
2. **Select "Database"**
3. **Choose "Redis"**
4. **Wait for deployment** (1-2 minutes)

### Step 4: Deploy NextCloud

1. **Click "Add Service"**
2. **Select "GitHub Repo"**
3. **Connect GitHub** (if not already connected)
4. **Choose your forked repository**
5. **Railway will auto-detect** the Dockerfile
6. **Add Database Reference Variables:**
   - Go to Variables tab
   - Add: `DATABASE_URL` = `${{MySQL.MYSQL_URL}}`
   - Add: `REDIS_URL` = `${{Redis.REDIS_URL}}`
   - (Replace service names with your actual service names)
7. **Click "Deploy"**

**Wait for deployment** (5-10 minutes for first build)

### Step 5: Verify Deployment

1. **Click on NextCloud service**
2. **Go to "Deployments" tab**
3. **Wait for "SUCCESS" status**
4. **Click the public URL**
5. **Complete NextCloud setup wizard**

### Step 6: Check Security Status

1. **After setup, go to NextCloud admin**
2. **Navigate to Settings → Administration → Overview**
3. **Should see mostly green checkmarks ✅**

## 🎉 Basic Deployment Complete!

Your NextCloud should now be running with:
- ✅ All security warnings resolved
- ✅ Performance optimizations enabled
- ✅ Redis caching configured
- ✅ Database indices optimized

---

## 📞 Optional: Add Talk High-Performance Backend

If you want video calling capabilities:

### Step 7: Deploy Talk HPB Service

1. **In same Railway project, click "Add Service"**
2. **Select "Docker Image"**
3. **Enter image**: `ghcr.io/nextcloud-releases/aio-talk:latest`
4. **Add environment variables**:

```
NC_DOMAIN = your-nextcloud-service-url.railway.app
SIGNALING_SECRET = [generate with: openssl rand -hex 32]
TURN_SECRET = [generate with: openssl rand -hex 32]  
INTERNAL_SECRET = [generate with: openssl rand -hex 32]
```

5. **Deploy the HPB service**

### Step 9: Connect HPB to NextCloud

1. **Go to NextCloud service**
2. **Add environment variables**:

```
SIGNALING_SECRET = [same as HPB SIGNALING_SECRET]
HPB_URL = https://your-hpb-service-url.railway.app
```

3. **Redeploy NextCloud service**

### Step 10: Configure Talk in NextCloud

1. **Go to NextCloud admin → Settings → Talk**
2. **Verify HPB connection shows green checkmark**
3. **Test video calls**

---

## 🔧 Environment Variables Summary

### Auto-provided by Railway:
- `DATABASE_URL` ✅ (from MySQL service)
- `REDIS_URL` ✅ (from Redis service)
- `RAILWAY_PUBLIC_DOMAIN` ✅ (your app URL)

### Optional (for Talk HPB):
- `SIGNALING_SECRET` (shared between NextCloud and HPB)
- `HPB_URL` (URL of your HPB service)

### HPB Service needs:
- `NC_DOMAIN` (your NextCloud domain)
- `SIGNALING_SECRET` (shared secret)
- `TURN_SECRET` (for TURN server)
- `INTERNAL_SECRET` (internal communication)

---

## 🚨 Common Issues & Solutions

### Issue: "Service not accessible via public URL"
**Solution**: 
- Ensure Public Networking is set to **HTTP** (not "Unexposed")
- Wait for deployment to complete fully (can take 5-10 minutes)
- Check Deploy Logs for any startup errors

### Issue: "Build fails or startup errors"
**Solution**: 
- Remove any Pre-deploy Command (like `npm run migrate`)
- Leave Custom Start Command empty
- Check deployment logs for specific error messages

### Issue: "Database connection failed"
**Solution**: Wait for MySQL service to fully deploy before starting NextCloud

### Issue: "Redis connection failed"  
**Solution**: Ensure Redis service is running and healthy

### Issue: Security warnings still show
**Solution**: Wait 10-15 minutes, restart NextCloud service if needed

### Issue: HPB not connecting
**Solution**: Verify SIGNALING_SECRET matches exactly between services

### Issue: File uploads fail
**Solution**: Check Railway storage limits, upgrade plan if needed

---

## 🎯 Final Checklist

After successful deployment:

- [ ] NextCloud accessible via public URL
- [ ] Admin setup wizard completed
- [ ] Security overview shows green checkmarks
- [ ] File upload/download works
- [ ] Talk app installed (if using HPB)
- [ ] Video calls work (if using HPB)

**🎉 Congratulations! You have a fully optimized NextCloud deployment!**
