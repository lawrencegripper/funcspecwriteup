# Rest Spec issue in Functions

I first encountered this issue when working on a change in `terraform` to [add the ability to list functions keys](https://github.com/terraform-providers/terraform-provider-azurerm/pull/4066)and [wrote it up here with a manual change to the Swagger which resolves the issue for the endpoint I used `WebApps_ListFunctionSecrets`](https://github.com/Azure/azure-rest-api-specs/issues/7143).

Here is a quick write up of the issue as it looks like it affects a number of the endpoints in the REST specs for both `2018-02-01` and `2018-08-01`. We'll focus on `2018-02-01` below to simplify things.

For details on how to reproduce these findings see 

- [./repro.md](./repro.md) for doing this in the CLI
- [./dotnetsample](./dotnetsample) showing issues when using the .NET SDK (also affects Golang as generated from same Spec)

# Initial `WebApps_ListFunctionSecrets` inconsistency

The [spec defines the call as follows](https://github.com/Azure/azure-rest-api-specs/blob/8a02736ee4e89d8115d4ed5d2001e8c8d78ca878/specification/web/resource-manager/Microsoft.Web/stable/2018-02-01/WebApps.json#L3105-L3153):

```json
"/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Web/sites/{name}/functions/{functionName}/listsecrets": {
      "post": {
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
    }
```

The response type referenced [`#/definitions/FunctionSecrets` is as follows](https://github.com/Azure/azure-rest-api-specs/blob/8a02736ee4e89d8115d4ed5d2001e8c8d78ca878/specification/web/resource-manager/Microsoft.Web/stable/2018-02-01/WebApps.json#L18896-L18920):

```json
    "FunctionSecrets": {
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
    },
```

If you use `az rest` to make a request to this API the response is:

```
az rest --method post 
-u /subscriptions/5774ad8f-0000-0000-a72e-0447910568d3/resourceGroups/funcRestSpecTest/providers/Microsoft.Web/sites/tesSOEMSITE8b7a/functions/testfunc/listsecrets?api-version=2018-02-01
```

```json
{
  "key": "LZro9c3Aq2HxICVG/somekey",
  "trigger_url": "https://something.azurewebsites.net/api/testfunc?code=LZro9ICVG/Wdbsomekey"
}
```

## Issue 1: Mismatched Body between REST Spec and Actual Response

### What is the impact?

In the generated SDKs (tested Go and .NET) the API is unusable as the result cannot be deserialized correctly.

### Details

The defined return type for `WebApps_ListFunctionSecrets` in the REST Spec has a body definition of `"#/definitions/FunctionSecrets"`. This is the following JSON:

```json
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
```

Translated to the response this defines an `EXPECTED` response from the API to be the following `json`:

```json
 {
   "properties": {
     "key": "LZro9c3Aq2HxICVG/somekey",
     "trigger_url": "https://something.azurewebsites.net/api/testfunc?code=LZro9ICVG/Wdbsomekey"
   }
 }
```

The `ACTUAL` response body is:

```json
{
  "key": "LZro9c3Aq2HxICVG/somekey",
  "trigger_url": "https://something.azurewebsites.net/api/testfunc?code=LZro9ICVG/Wdbsomekey"
}
```

The `DIFF` is that the spec incorrectly expects the `key` and `trigger` properties to be under a parent `properties` object which they aren't. 

```diff
{
-   "properties": {
   "key": "LZro9c3Aq2HxICVG/somekey",
   "trigger_url": "https://something.azurewebsites.net/api/testfunc?code=LZro9ICVG/Wdbsomekey"
-   }
 }
```

### How does the Function CLI do this?

I went to look at the code for the [func cli](https://github.com/Azure/azure-functions-core-tools/blob/9cc58db73732bf17364c151be822036f52c78cd4/src/Azure.Functions.Cli/Helpers/AzureHelper.cs#L143-L161) to look at how it gets keys back. 

You can see from the code that it also looks for a top level value of `keys` in the response and not `properties.keys` as defined in the spec. 

```csharp
        internal static async Task<string> GetFunctionKey(string functionName, string appId, string accessToken, string managementURL)
        {
            // If anything goes wrong anywhere, simply return null and let the caller take care of it.
            if (string.IsNullOrEmpty(functionName) || string.IsNullOrEmpty(accessToken))
            {
                return null;
            }
            var url = new Uri($"{managementURL}{appId}/hostruntime/admin/functions/{functionName}/keys?api-version={ArmUriTemplates.WebsitesApiVersion}");
            var key = string.Empty;
            try
            {
                var keysJson = await ArmHttpAsync<JToken>(HttpMethod.Get, url, accessToken);
                key = (string)(keysJson["keys"] as JArray).First()["value"];
            }
            catch (Exception)
            {
                return null;
            }
            return key;
        }
```


## Issue 2: Incorrect addition of properties in the REST Spec 

### What is the impact?

In the generated SDKs (tested Go and .NET) the API has additional confusing properties on request that don't make sense and are never deserialised to. 

## Details


The defined return type for `WebApps_ListFunctionSecrets` in the REST Spec has a body definition of `"#/definitions/FunctionSecrets"`.

Before the return body definition it has a reference to [`allOf`](https://swagger.io/docs/specification/data-models/oneof-anyof-allof-not/) these add additional properties from another definition onto the object. 

```json
    "allOf": [
        {
          "$ref": "./CommonDefinitions.json#/definitions/ProxyOnlyResource"
        }
    ],
```

The `"./CommonDefinitions.json#/definitions/ProxyOnlyResource"` is as follows:

```json
    "ProxyOnlyResource": {
      "description": "Azure proxy only resource. This resource is not tracked by Azure Resource Manager.",
      "properties": {
        "id": {
          "description": "Resource Id.",
          "type": "string",
          "readOnly": true
        },
        "name": {
          "description": "Resource Name.",
          "type": "string",
          "readOnly": true
        },
        "kind": {
          "description": "Kind of resource.",
          "type": "string"
        },
        "type": {
          "description": "Resource type.",
          "type": "string",
          "readOnly": true
        }
      },
      "x-ms-azure-resource": true
    },
```


Translated to the response this defines an `EXPECTED` response from the API to be the following `json` (including body defined and discussed in Issue 1):

```json
 {
   "id": "someid",
   "name": "somename",
   "kind": "somekind",
   "type": "sometype",
   "properties": {
     "key": "LZro9c3Aq2HxICVG/somekey",
     "trigger_url": "https://something.azurewebsites.net/api/testfunc?code=LZro9ICVG/Wdbsomekey"
   }
 }
```

The `ACTUAL` response body is:

```json
{
  "key": "LZro9c3Aq2HxICVG/somekey",
  "trigger_url": "https://something.azurewebsites.net/api/testfunc?code=LZro9ICVG/Wdbsomekey"
}
```

The `DIFF` is that the `allOf` statement has incorrectly included 4 additional 

```diff
 {
-   "id": "someid",
-   "name": "somename",
-   "kind": "somekind",
-   "type": "sometype",
-  "properties": {        // Ignore: Introduce by Issue 1
     "key": "LZro9c3Aq2HxICVG/somekey",
     "trigger_url": "https://something.azurewebsites.net/api/testfunc?code=LZro9ICVG/Wdbsomekey"
-   }                     // Ignore: Introduce by Issue 1
 }
```


## Repeated issue in newer APIs

While investigating the issue I was pointed to a newer set of APIs here: https://github.com/Azure/azure-rest-api-specs/pull/7174#issuecomment-325438810

This includes a repeat of the above issue on a number of new APIS:

- POST api/sites/{name}[/slots/{slot}]/functions/{functionName}/listkeys
- PUT api/sites/{name}[/slots/{slot}]/functions/{functionName}/keys/{keyName}
- DELETE api/sites/{name}[/slots/{slot}]/functions/{functionName}/keys/{keyName}
- POST api/sites/{name}[/slots/{slot}]/host/default/listkeys
- PUT api/sites/{name}[/slots/{slot}]/host/default/{functionkeys|systemkeys}/{keyName}
- DELETE api/sites/{name}[/slots/{slot}]/host/default/{functionkeys|systemkeys}/{keyName}
- POST api/sites/{name}[/slots/{slot}]/host/default/sync
- POST api/sites/{name}[/slots/{slot}]/host/default/listsyncstatus
- GET api/sites/{name}[/slots/{slot}]/functions/{functionName}/properties/state
- PUT api/sites/{name}[/slots/{slot}]/functions/{functionName}/properties/state
- GET api/sites/{name}[/slots/{slot}]/functions/{functionName}/properties/status
- GET api/sites/{name}[/slots/{slot}]/host/default/properties/config
- GET api/sites/{name}[/slots/{slot}]/host/default/properties/status

Local copy of changes in [./testdata/2091OR7174WebApps.json](./testdata/2091OR7174WebApps.json)

## Example 1: OperationID `WebApps_ListHostKeys`

### Details

The defined return type for `WebApps_ListHostKeys` in the REST Spec has a definition of `"#/definitions/HostKeys"`. This is the following `JSON`:

```json
{
  "description": "Functions host level keys.",
  "type": "object",
  "allOf": [
    {
      "$ref": "./CommonDefinitions.json#/definitions/ProxyOnlyResource"
    }
  ],
  "properties": {
    "properties": {
      "description": "HostKeys resource specific properties",
      "properties": {
        "masterKey": {
          "description": "Secret key.",
          "type": "string"
        },
        "functionKeys": {
          "description": "Host level function keys.",
          "type": "object",
          "additionalProperties": {
            "type": "string"
          }
        },
        "systemKeys": {
          "description": "System keys.",
          "type": "object",
          "additionalProperties": {
            "type": "string"
          }
        }
      },
      "x-ms-client-flatten": true
    }
  }
}
```

Translated to the response this defines an `EXPECTED` response from the API to be the following `json`:

```json
 {
   "id": "someid",
   "name": "somename",
   "kind": "somekind",
   "type": "sometype",
   "properties": {
     "masterkey": "LZro9c3Aq2HxICVG/somekey",
     "functionKeys": {},
     "systemKeys": {}
   }
 }
```

Making a request with `az rest --method post -u /subscriptions/somesub-d51e-4456-a72e-0447910568d3/resourceGroups/funcRestSpecTest/providers/Microsoft.Web/sites/somesite/host/default/listkeys?api-version=2018-02-01`.

The `ACTUAL` response body is:

```json
{

  "functionKeys": {
    "default": "KJvuWBMHd8O0sXuB5qFkKCPUuMR//VCPcvoyXsVNnnxWsR9lfqIqHA=="
  },
  "masterKey": "8mHmW6CjbiFdt1pJrnxJ3bty5zWNScw6qPFEvaFUl20cpSm4pCeHhg==",
  "systemKeys": {
    "eventgridextensionconfig_extension": "/QMEve5NWSdZ89Or2kf/ET56HmPXmoDe1E6WoRuM0cSN240i6GhIqA=="
  }
}
```

## Other issues Seen in PR: https://github.com/Azure/azure-rest-api-specs/pull/7174#issuecomment-325438810

### Incorrect content values set on: `WebApps_ListSyncStatus` 

`DEFINITION`: POST api/sites/{name}[/slots/{slot}]/host/default/listsyncstatus

This shows that the responses will be statusCode of `204` with `No Content`

```json
{
  "tags": [
    "WebApps"
  ],
  "summary": "This is to allow calling via powershell and ARM template.",
  "description": "This is to allow calling via powershell and ARM template.",
  "operationId": "WebApps_ListSyncStatus",
  "parameters": [
    {
      "$ref": "#/parameters/resourceGroupNameParameter"
    },
    {
      "name": "name",
      "in": "path",
      "description": "Name of the app.",
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
    "204": {
      "description": "No Content"
    }
  }
}
```

`Actual` Response looks returns a `200` with a body of:

```json
{
  "status": "success"
}
```

Making a request with `az rest --method post -u /subscriptions/somesub-d51e-4456-a72e-0447910568d3/resourceGroups/funcRestSpecTest/providers/Microsoft.Web/sites/somesite/host/default/listsyncstatus?api-version=2018-02-01 --debug`

Raw:

```
urllib3.connectionpool : https://management.azure.com:443 "POST /subscriptions/somesub-d51e-4456-a72e-0447910568d3/resourceGroups/funcRestSpecTest/providers/Microsoft.Web/sites/somesite/host/default/listsyncstatus?api-version=2018-02-01 HTTP/1.1" 200 None
Event: CommandInvoker.OnTransformResult [<function _resource_group_transform at 0x7fdf26468488>, <function _x509_from_base64_to_hex_transform at 0x7fdf26468510>]
Event: CommandInvoker.OnFilterResult []
{
  "status": "success"
}

```
