# Azure-Databricks-Token-Rotation
A script that will rotate Databricks tokens.  When running jobs in Databricks, you need a token.  You should create a "job" user account (e.g. Azure AD account) and use this script to rotate the tokens under that account.

## See the script for the documentation
The script includes step by step instructions.
https://github.com/AdamPaternostro/Azure-Databricks-Token-Rotation/blob/master/Databricks-Token-Rotation.sh

The basics:
* You will have a key vault for IT admins (this will contain a Databricks token for Admin access to Databricks).  We do not want developers in here.
* You will have a key vault for Developers (this will contain the most recent Databricks token for Developers to access Databricks).  The key vault will aslo store the "id" of this latest token.
* In Databricks under the Admin account you will have a single token (this gets rotated everytime the script runs)
* In Databricks under the Developer account, you will have two tokens.  One of the tokens will be the "lastest" and will be in key vault (along with its id).  The other token will be prior-latest token (this token should be "draining" from use).  We cannot immediately delete the prior-latest token since stuff might break, so we create a new token (aka latest), leave the old one around to drain (aka prior-latest) and delete all other tokens (prior-prior-latest and such).

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
