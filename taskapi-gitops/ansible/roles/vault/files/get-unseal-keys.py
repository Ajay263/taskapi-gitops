import json, sys
data = json.load(open('/home/azureuser/.vault-init.json'))
keys = data['unseal_keys_b64'][:3]
for k in keys:
    print(k)
