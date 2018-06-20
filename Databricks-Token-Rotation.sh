#!/bin/bash

####################################################################
# What this does
#   We need to rotate the tokens the developers are using in Databricks
#   We need a token in order to call the Databricks API (this is called the Admin token)
#   So, we have a ADMIN token that rotates everytime this script is run. 
#   The ADMIN token is stored in a KeyVault that only sysadmin's have access.
#   We also have DEVELOPER tokens.  We will store the latest value in a KeyVault which developers have access.
#   We will have two developer tokens.  One is the one that is currently in use.
#   We need to keep the one that is in use and then generate a second one.
#   The second one will be used to update the developer's KeyVault.  
#   When new code isrun it will use the new token.  
#   The prior token will be slowly deprecated (and deleted the next time this script is run).
# NOTE: Running this script twice in a row will generate two new developer tokens and delete the "current in use" one.
#       You should run this script every {x} days based upon how often your code retreieves a new token.
#       For Example: If your code gets a new token every hour then you could run this script every hour.  
####################################################################


################################
# Initial one-time setup (you must do this by hand)
#   Install Curl: https://curl.haxx.se/download.html
#   Install "jq": https://stedolan.github.io/jq/download/
# In Databricks:
#   Create the following tokens:
#   DATABRICKS-ADMIN-TOKEN          e.g. dapi11286e379e72323b3b5e70d5555db5b9
#   DATABRICKS-DEVELOPER-TOKEN      e.g. dapi44b8f349678e6eb0b1221f8af4cbfb92  (also note the token id - first column, view the HTML source if you have to)
# In Azure
#   Create a KeyVault (for Admins)
#   Create a secert named: DATABRICKS-ADMIN-TOKEN        with a value of <<DATABRICKS-ADMIN-TOKEN>>
#   Create a KeyVault (for Developers)
#   Create a secert named: DATABRICKS-DEVELOPER-TOKEN    with a value of <<DATABRICKS-DEVELOPER-TOKEN>>
#   Create a secert named: DATABRICKS-DEVELOPER-TOKEN-ID with a value of <<DATABRICKS-DEVELOPER-TOKEN>> token id (from Databricks protal)
################################


####################################################################
# Variables
####################################################################
# This service principle must have access to both KeyVaults
tenant_id=<<REMOVED>>
client_id=<<REMOVED>>
client_secret=<<REMOVED>>

# KeyVault names
keyvault_admin=<<REMOVED>>
keyvault_developer=<<REMOVED>>

# How many seconds the Databricks token should be valid for (this is 90 days)
lifetime_seconds=7776000


####################################################################
# Login to Azure AD
####################################################################
token=$(curl -X POST https://login.microsoftonline.com/$tenant_id/oauth2/token \
  -F resource=https://vault.azure.net \
  -F client_id=$client_id \
  -F grant_type=client_credentials \
  -F client_secret=$client_secret | jq .access_token --raw-output) 


####################################################################
# Admin token (rotate the admin token, no one really needs to every see this)
####################################################################

#-------------------------------
# Get the Admin Databricks token from KeyVault
#-------------------------------
DATABRICKS_ADMIN_TOKEN=$(curl -X GET "https://${keyvault_admin}.vault.azure.net/secrets/DATABRICKS-ADMIN-TOKEN?api-version=2016-10-01" \
  -H "Authorization: Bearer $token" | jq -r .value)

echo "DATABRICKS_ADMIN_TOKEN = $DATABRICKS_ADMIN_TOKEN"

#-------------------------------
# Generate a new Admin Databricks token
#-------------------------------
NEW_DATABRICKS_ADMIN_TOKEN_JSON=$(curl 'https://eastus2.azuredatabricks.net/api/2.0/token/create' \
  -H "Authorization: Bearer $DATABRICKS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{ \"lifetime_seconds\": $lifetime_seconds, \"comment\": \"DATABRICKS-ADMIN-TOKEN\" }")

NEW_DATABRICKS_ADMIN_TOKEN_VALUE=$(echo $NEW_DATABRICKS_ADMIN_TOKEN_JSON | jq -r .token_value)
NEW_DATABRICKS_ADMIN_TOKEN_ID=$(echo $NEW_DATABRICKS_ADMIN_TOKEN_JSON | jq -r .token_info.token_id)

echo "NEW_DATABRICKS_ADMIN_TOKEN_JSON  = $NEW_DATABRICKS_ADMIN_TOKEN_JSON"
echo "NEW_DATABRICKS_ADMIN_TOKEN_VALUE = $NEW_DATABRICKS_ADMIN_TOKEN_VALUE"
echo "NEW_DATABRICKS_ADMIN_TOKEN_ID    = $NEW_DATABRICKS_ADMIN_TOKEN_ID"

#-------------------------------
# Update KeyVault with the new Admin Databricks token
#-------------------------------
curl -X PUT "https://${keyvault_admin}.vault.azure.net/secrets/DATABRICKS-ADMIN-TOKEN?api-version=2016-10-01" \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  -d "{ \"value\": \"$NEW_DATABRICKS_ADMIN_TOKEN_VALUE\" }"

echo "Updated KeyVault with the new Admin Databricks token"

#-------------------------------
# Delete the prior Admin Databricks token from Databricks
# Get all the admin tokens that have a comment of "DATABRICKS-ADMIN-TOKEN" and do not have a Token Id of {NEW_DATABRICKS_ADMIN_TOKEN_ID}
#-------------------------------
ALL_ADMIN_TOKENS_JSON=$(curl 'https://eastus2.azuredatabricks.net/api/2.0/token/list' \
  -X GET -H "Authorization: Bearer $NEW_DATABRICKS_ADMIN_TOKEN_VALUE")

echo "ALL_ADMIN_TOKENS_JSON = $ALL_ADMIN_TOKENS_JSON"

#echo $ALL_ADMIN_TOKENS_JSON \
#  | jq .token_infos \
#  | jq -c 'map(select(.comment  == "DATABRICKS-ADMIN-TOKEN"))' \
#  | jq -r .[].token_id

for row in $(echo $ALL_ADMIN_TOKENS_JSON \
            | jq .token_infos \
            | jq -c 'map(select(.comment  == "DATABRICKS-ADMIN-TOKEN"))' \
            | jq -r .[].token_id); do
  if [ "${row}" = "$NEW_DATABRICKS_ADMIN_TOKEN_ID" ]; then
    echo "Admin token - Skipping: ${row}"
  else
    echo "Admin token - Deleting: ${row}"
    curl -X POST 'https://eastus2.azuredatabricks.net/api/2.0/token/delete' \
      -H "Authorization: Bearer $NEW_DATABRICKS_ADMIN_TOKEN_VALUE" \
      -H "Content-Type: application/json" \
      -d "{ \"token_id\": \"${row}\" }"
  fi
done


####################################################################
# Developer Token
# We will have two developer tokens.  A new one and the one currently in use.
####################################################################

#-------------------------------
# Get the current token id of the developer token 
#-------------------------------
CURRENT_DATABRICKS_DEVELOPER_TOKEN_ID=$(curl -X GET "https://${keyvault_developer}.vault.azure.net/secrets/DATABRICKS-DEVELOPER-TOKEN-ID?api-version=2016-10-01" \
  -H "Authorization: Bearer $token" | jq -r .value)

echo "CURRENT_DATABRICKS_DEVELOPER_TOKEN_ID = $CURRENT_DATABRICKS_DEVELOPER_TOKEN_ID"

#-------------------------------
# Generate a new developer token
#-------------------------------
NEW_DATABRICKS_DEVELOPER_TOKEN_JSON=$(curl 'https://eastus2.azuredatabricks.net/api/2.0/token/create' \
  -H "Authorization: Bearer $NEW_DATABRICKS_ADMIN_TOKEN_VALUE" \
  -H "Content-Type: application/json" \
  -d "{ \"lifetime_seconds\": $lifetime_seconds, \"comment\": \"DATABRICKS-DEVELOPER-TOKEN\" }")

NEW_DATABRICKS_DEVELOPER_TOKEN_VALUE=$(echo $NEW_DATABRICKS_DEVELOPER_TOKEN_JSON | jq -r .token_value)
NEW_DATABRICKS_DEVELOPER_TOKEN_ID=$(echo $NEW_DATABRICKS_DEVELOPER_TOKEN_JSON | jq -r .token_info.token_id)

echo "NEW_DATABRICKS_DEVELOPER_TOKEN_JSON  = $NEW_DATABRICKS_DEVELOPER_TOKEN_JSON"
echo "NEW_DATABRICKS_DEVELOPER_TOKEN_VALUE = $NEW_DATABRICKS_DEVELOPER_TOKEN_VALUE"
echo "NEW_DATABRICKS_DEVELOPER_TOKEN_ID    = $NEW_DATABRICKS_DEVELOPER_TOKEN_ID"

#-------------------------------
# Update KeyVault with the new Developer token
# Keep the developer token in their keyvault and keep the token id 
#-------------------------------
curl -X PUT "https://${keyvault_developer}.vault.azure.net/secrets/DATABRICKS-DEVELOPER-TOKEN?api-version=2016-10-01" \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  -d "{ \"value\": \"$NEW_DATABRICKS_DEVELOPER_TOKEN_VALUE\" }"

curl -X PUT "https://${keyvault_developer}.vault.azure.net/secrets/DATABRICKS-DEVELOPER-TOKEN-ID?api-version=2016-10-01" \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  -d "{ \"value\": \"$NEW_DATABRICKS_DEVELOPER_TOKEN_ID\" }"

echo "Updated KeyVault with the new Developer token"

#-------------------------------
# Delete any prior developer tokens
# We need to keep the new one just generated and the one that is currently is use
#-------------------------------
ALL_DEVELOPER_TOKENS_JSON=$(curl 'https://eastus2.azuredatabricks.net/api/2.0/token/list' \
  -X GET -H "Authorization: Bearer $NEW_DATABRICKS_ADMIN_TOKEN_VALUE")

echo "ALL_DEVELOPER_TOKENS_JSON = $ALL_DEVELOPER_TOKENS_JSON"

#echo $ALL_DEVELOPER_TOKENS_JSON \
#  | jq .token_infos \
#  | jq -c 'map(select(.comment  == "DATABRICKS-DEVELOPER-TOKEN"))' \
#  | jq -r .[].token_id

for row in $(echo $ALL_DEVELOPER_TOKENS_JSON \
            | jq .token_infos \
            | jq -c 'map(select(.comment  == "DATABRICKS-DEVELOPER-TOKEN"))' \
            | jq -r .[].token_id); do
  if [ "${row}" = "$CURRENT_DATABRICKS_DEVELOPER_TOKEN_ID" ] || [ "${row}" = "$NEW_DATABRICKS_DEVELOPER_TOKEN_ID" ] ; then
    echo "Developer token - Skipping: ${row}"
  else
    echo "Developer token - Deleting: ${row}"
    curl -X POST 'https://eastus2.azuredatabricks.net/api/2.0/token/delete' \
      -H "Authorization: Bearer $NEW_DATABRICKS_ADMIN_TOKEN_VALUE" \
      -H "Content-Type: application/json" \
      -d "{ \"token_id\": \"${row}\" }"
  fi
done
