# Reproduce

Deploy the same which creates a function called `testfunc`, I've used `terraform` but you can do it with ARM, CLI or the Portal just ensure the `testdata/testfunc.zip` is deployed so the function is present. The scripts are run in `bash` and assume `azure cli` is installed and logged in. 

```bash
terraform init
terraform apply -auto-approve
```

The terraform will return the REST endpoints that we'll need to make the calls once the deployment is finished. For example:

```
11:52 $ terraform output function_endpoint
/subscriptions/5774ad8f-d51e-4456-a72e-0447910568d3/resourceGroups/funcRestSpecTest/providers/Microsoft.Web/sites/testfuncx8b7a/functions/testfunc
```

We then set this to an variable to make subsequent calls easier. 

```bash
FUNCENDPOINT=`terraform output function_endpoint`
```

## Make a call and compare

In this example we'll look at the `operationID=WebApps_ListFunctionSecrets` call

1. Make the call to the endpoint

```bash
FUNCENDPOINT=`terraform output function_endpoint`
az rest --method post -u $FUNCENDPOINT/listsecrets?api-version=2018-02-01
{
  "key": "LZro9c3Aq2HxICSomekey",
  "trigger_url": "https://somesite.azurewebsites.net/api/testfunc?code=LZro9c3Aq2somekey"
}
```

2. Compare to the calls defined in the spec 

First get the Request 
```
OPERATIONID=WebApps_ListFunctionSecrets
jq ".paths | .[] | .[] | select(.operationId == \"$OPERATIONID\")" testdata/02-01WebApps.json
```

This returns 

```json
{
  "tags": [
    "WebApps"
  ],
  "summary": "Get function secrets for a function in a web site, or a deployment slot.",
  "description": "Get function secrets for a function in a web site, or a deployment slot.",
  "operationId": "WebApps_ListFunctionSecrets",
  "parameters": [
    {
      "$ref": "#/parameters/resourceGroupNameParameter"
    },
    {
      "name": "name",
      "in": "path",
      "description": "Site name.",
      "required": true,
      "type": "string"
    },
    {
      "name": "functionName",
      "in": "path",
      "description": "Function name.",
      "required": true,
      "type": "string"
    },
    {
      "$ref": "#/parameters/subscriptionIdParameter"
    },
    {
      "$ref": "#/parameters/apiVersionParameter"
    }
  ],
  "responses": {
    "200": {
      "description": "Function secrets returned.",
      "schema": {
        "$ref": "#/definitions/FunctionSecrets"
      }
    },
    "default": {
      "description": "App Service error response.",
      "schema": {
        "$ref": "./CommonDefinitions.json#/definitions/DefaultErrorResponse"
      }
    }
  }
}
```

Now take the returned response reference `"$ref": "#/definitions/FunctionSecrets"` and use this to get the response, you can look it up manually or use `JQ`

```
DEFNAME=FunctionSecrets
jq ".definitions.$DEFNAME" testdata/02-01WebApps.json
```


The result is 

```json
{
  "description": "Function secrets.",
  "type": "object",
  "allOf": [
    {
      "$ref": "./CommonDefinitions.json#/definitions/ProxyOnlyResource"
    }
  ],
  "properties": {
    "properties": {
      "description": "FunctionSecrets resource specific properties",
      "properties": {
        "key": {
          "description": "Secret key.",
          "type": "string"
        },
        "trigger_url": {
          "description": "Trigger URL.",
          "type": "string"
        }
      },
      "x-ms-client-flatten": true
    }
  }
}
```

