# notes

## kong
version: 3.1, mode: dbless

## create keypair for jwt credentials
described at https://docs.konghq.com/hub/kong-inc/jwt/

openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -outform PEM -pubout -out public.pem

## access kong admin-api
export admin-api: set KONG_ADMIN_LISTEN and attach related ports on proxy, deploy kong-admin service
kubectl port-forward svc/kong-admin 8765:8001 -n kong
then you can access kong admin-api (https://docs.konghq.com/gateway/api/admin-ee/latest/)
e.g.: curl -v -X GET http://localhost:8765/consumers, list all consumerswhich KongConsumers defined & created, get their consumer-ids

## create jwt credentials:
create jwt credentails by kong admin-api:
curl -X POST http://localhost:8765/consumers/15767db4-f0e4-5904-bd07-78ba65140ca6/jwt -F "rsa_public_key=./public.pem"
because kong is in dbless mode, so it's impossible and there will be errors like:
{"code":12,"message":"cannot create 'jwt_secrets' entities when not using a database","name":"operation unsupported"}

When you created correct format secret used by KongConsumer, then you can list all related jwt credentials by admin-api:
curl -v -X GET http://localhost:8765/consumers/15767db4-f0e4-5904-bd07-78ba65140ca6/jwt
response format:
{
  "data": [
    {
      "key": "a3fc3049b36249a8c9f8891cb127243c",
      "tags": null,
      "rsa_public_key": "-----BEGIN PUBLIC KEY...",
      "created_at": 1732157763,
      "algorithm": "RS256",
      "consumer": {
        "id": "15767db4-f0e4-5904-bd07-78ba65140ca6"
      },
      "secret": "oDwanhPUSIw7R39jJpW11HdFNQYbalPI",
      "id": "6cee413e-443f-5643-a2e8-5dd12b2692fb"
    },
    {
      "key": "a36c3039b36249a3c9f88910b127243c",
      "tags": null,
      "rsa_public_key": "-----BEGIN PUBLIC KEY...",
      "created_at": 1732157763,
      "algorithm": "RS256",
      "consumer": {
        "id": "15767db4-f0e4-5904-bd07-78ba65140ca6"
      },
      "secret": "wbMfFPlI9hFvqdktniL6EihqhwP4ZcHX",
      "id": "cf54da9f-5695-5f37-88e9-89a9056c8261"
    }
  ],
  "next": null
}

apiVersion: v1
kind: Secret
metadata:
  name: jwt-key-0
  namespace: kong-app
  labels:
    konghq.com/credential: jwt # critical label field
data:
  algorithm: UlMyNTY=
  claims_to_verify: ZXhwLG5iZg==
  key: YTNmYzMwNDliMzYy...
  kongCredType: and0 # critical data field
  rsa_public_key: LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0...

## issue fixed
curl -v -L -H 'Authorization: Bearer eyJhbGciOi...' http://kong-proxy.<domain>.net/mock-url/headers will trigger redirect and issue another request to this URL: 'https://kong-proxy.<domain>.net/mock-url/headers'. Authorization header will be lost during this redirect, so use command below to initiate the request directly without redirect:
curl -v -H 'Authorization: Bearer eyJhbGciOi...' https://kong-proxy.<domain>.net/mock-url/headers
