# notes
## kong
version: 3.1.1.6, mode: dbless
https://docs.konghq.com/gateway/3.1.x/install/kubernetes/proxy/

helm install kong-dp kong/kong -n kong --version 2.42.0 --values ./values-dp.yaml
helm list -n kong
NAME   	NAMESPACE	REVISION	UPDATED                             	STATUS  	CHART      	APP VERSION
kong-dp	kong     	1       	2024-11-19 06:42:51.854566 +0800 CST	deployed	kong-2.42.0	3.7

## jwt credentials
described at https://docs.konghq.com/hub/kong-inc/jwt/

openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -outform PEM -pubout -out public.pem

export admin-api: set KONG_ADMIN_LISTEN and attach related ports on proxy, deploy kong-admin service
kubectl port-forward svc/kong-admin 8765:8001 -n kong
then you can access kong admin-api (https://docs.konghq.com/gateway/api/admin-ee/latest/)
e.g.: curl -v -X GET http://localhost:8765/consumers, list all consumerswhich KongConsumers defined & created, get their consumer-ids

how to create jwt credentials:
create jwt credentails by kong admin-api:
curl -X POST http://localhost:8765/consumers/15767db4-f0e4-5904-bd07-78ba65140ca6/jwt -F "rsa_public_key=./public.pem"
because kong is in dbless mode, so it's impossible and there will be errors like:
{"code":12,"message":"cannot create 'jwt_secrets' entities when not using a database","name":"operation unsupported"}
When you created correct format secret used by KongConsumer, then you can list all related jwt credentials by admin-api:
curl -v -X GET http://localhost:8765/consumers/15767db4-f0e4-5904-bd07-78ba65140ca6/jwt
apiVersion: v1
kind: Secret
metadata:
  name: jwt-key-0
  namespace: kong-app
  labels:
    konghq.com/credential: enhanced-jwt # # critical label field
data:
  algorithm: UlMyNTY=
  claims_to_verify: ZXhwLG5iZg==
  key: YTNmYzMwNDliMzYy...
  kongCredType: and0 # critical data field
  rsa_public_key: LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0...
