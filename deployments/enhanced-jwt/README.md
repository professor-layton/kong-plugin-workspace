# notes
## kong
version: 3.1.1.6, mode: dbless
https://docs.konghq.com/gateway/3.1.x/install/kubernetes/proxy/

helm install kong-dp kong/kong -n kong --version 2.42.0 --values ./values-dp.yaml
helm list -n kong
NAME   	NAMESPACE	REVISION	UPDATED                             	STATUS  	CHART      	APP VERSION
kong-dp	kong     	1       	2024-11-19 06:42:51.854566 +0800 CST	deployed	kong-2.42.0	3.7
