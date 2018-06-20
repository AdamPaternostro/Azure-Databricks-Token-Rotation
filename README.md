# Azure-Databricks-Token-Rotation
A script that will rotate Databricks tokens.  This script will allow you to rotate the tokens that developers use when accessing Azure Databricks.  

## See the script for the documentation
The script includes step by step instructions.
https://github.com/AdamPaternostro/Azure-Databricks-Token-Rotation/blob/master/Databricks-Token-Rotation.sh


## The Developer's can then access their Databricks token
1 - The can use a service princple (login to Azure) and then call KeyVault
```
tenant_id=<<REMOVED>>
client_id=<<REMOVED>>
client_secret=<<REMOVED>>
keyvault_developer=<<REMOVED>>

token=$(curl -X POST https://login.microsoftonline.com/$tenant_id/oauth2/token \
  -F resource=https://vault.azure.net \
  -F client_id=$client_id \
  -F grant_type=client_credentials \
  -F client_secret=$client_secret | jq .access_token --raw-output) 
  
DATABRICKS_DEVELOPER_TOKEN=$(curl -X GET "https://${keyvault_developer}.vault.azure.net/secrets/DATABRICKS-DEVELOPER-TOKEN?api-version=2016-10-01" \
  -H "Authorization: Bearer $token" | jq -r .value)
```

2 - Or (better yet), they can use Managed Service Identity to get the token
```
keyvault_developer=<<REMOVED>>

token=$(curl http://localhost:50342/oauth2/token --data "resource=https://vault.azure.net" -H Metadata:true | jq .access_token --raw-output) 

DATABRICKS_DEVELOPER_TOKEN=$(curl https://${keyvault_developer}.vault.azure.net/secrets/DATABRICKS-DEVELOPER-TOKEN?api-version=2016-10-01 -H "Authorization: Bearer $token" | jq .value --raw-output) 
```
