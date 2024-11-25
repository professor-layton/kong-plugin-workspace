apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: consumer-user1
  namespace: kong-app
  annotations:
    kubernetes.io/ingress.class: kong
username: user0
credentials:
- jwt-key-0
