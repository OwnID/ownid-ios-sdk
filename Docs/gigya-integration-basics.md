# Gigya Integration Basics
An application using Gigya as its identity platform can use an OwnID SDK to simplify and streamline the login experience for its users. Before incorporating the "Skip Password" feature into an application, you need to create a dedicated Gigya application, create an OwnID application, and modify the Gigya schema.

## Create Gigya Application
OwnID strongly recommends that you create a new Gigya application that is dedicated to the OwnID integration. Once you have created this application, collect its identifying information (site data center, site API key, user key, and application secret) so you can define them in an OwnID application.

## Create OwnID Application
To create an OwnID application that is linked to the Gigya application:
1. Open the [OwnID Console](https://console.ownid.com/) and create an account or log in to an existing account.
2. Select **Create Application**.
3. Define the details of the OwnID application, and select **Next**.
4. Select the **SAP Customer Data Cloud** card, and select **Next**.
5. Enter the data center, site API key, and application key and secret. Note that the application key refers to the user key of the Gigya application.

## Modify Gigya Schema
Gigya includes a schema that stores all of your users' data. To integrate OwnID with Gigya, you need to add custom fields to this Gigya schema. You could create these fields one-by-one, but this is tedious and prone to error. To simplify the effort, Gigya accepts an API call that automatically adds the fields to the schema, allowing you to use a REST client like Postman to accomplish the task.  To add the custom fields to the schema:
1. Open Postman and switch to the workspace where you want to import a collection. If you are new to Postman, you can start with the [Postman documentation](https://learning.postman.com/docs).
2. Select the following button to import the collection that contains the required API call:
[![Run in Postman](https://run.pstmn.io/button.svg)](https://app.getpostman.com/run-collection/969bef2743d5297a92d5)
3. In Postman, use the drop-down to select the **OwnID-Gigya Integration** environment, and then select the Quick Look icon to open the variables of the environment. If you prefer, you can use the current environment and manually create each variable in the next step.
4. Define the variables used by the API request (`datacenter`, `apiKey`, `userKey`, and `secret`). The values of these variables match the values defined in your new OwnID application with one exception: if you are using a Gigya site group, `apiKey` must be the API Key of the parent site, not the child site.  Note that `userKey` refers to the Gigya application key. For more information about defining variables in Postman, see [Using Variables](https://learning.postman.com/docs/sending-requests/variables/).
5. Send the API request.

You can now check the Gigya schema to verify that the request successfully added the custom fields. Open your site in the Gigya console and select **Schema** in the left-hand navigation pane. You should see the schema fields under **accounts > data > ownid**.
