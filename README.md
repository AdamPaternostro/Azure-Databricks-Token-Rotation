# Azure-Databricks-Token-Rotation
A script that will rotate Databricks tokens.  This script will allow you to rotate the tokens that developers use when accessing Azure Databricks.  

## See the script for the documentation
The script includes step by step instructions.


## The Developer's can then access their Databricks token
1 - The can use a service princple (login to Azure) and then call KeyVault
```
DATABRICKS_DEVELOPER_TOKEN=$(curl -X GET "https://${keyvault_developer}.vault.azure.net/secrets/DATABRICKS-DEVELOPER-TOKEN?api-version=2016-10-01" \
  -H "Authorization: Bearer $token" | jq -r .value)
```

2 - Or (better yet), they can use Managed Service Identity to get the token
```
token=$(curl http://localhost:50342/oauth2/token --data "resource=https://vault.azure.net" -H Metadata:true | jq .access_token --raw-output) 
DATABRICKS_DEVELOPER_TOKEN=$(curl https://${keyvault_developer}.vault.azure.net/secrets/DATABRICKS-DEVELOPER-TOKEN?api-version=2016-10-01 -H "Authorization: Bearer $token" | jq .value --raw-output) 
```
