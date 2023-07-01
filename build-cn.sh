#1/bin/bash
docker buildx build -t ccr.ccs.tencentyun.com/karasu/stck:soapy-remote --network host -f Dockerfile.cn .