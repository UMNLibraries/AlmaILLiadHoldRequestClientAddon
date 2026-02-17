# AlmaILLiadHoldRequestClientAddon
ILLiad client addon for creation of items holds in Alma

Description:
This ILLiad addon allows staff to request physical item holds in Ex Libris Alma directly from the ILLiad client using the item barcode. It also supports checking the status of that request and cancelling it.

---

## PREREQUISITES

1. An Ex Libris Alma API Key with Read/Write permissions for the "Bibs" enpoints.
2. The base URL for your Alma API region (e.g., [https://api-na.hosted.exlibrisgroup.com/almaws/v1/]()).
3. ILLiad Client Version 9.2 or higher (recommended).

---

## INSTALLATION

1. Download zip.
2. Navigate to ILLiad directory (C:\Program Files (x86)\ILLiad\Addons
3. Copy zip file and extract.
4. Ensure the addon is "Active" in ILLiad Client > System > Manage Addons.

---

## CONFIGURATION SETTINGS

Once installed, configure the following settings in the addon settings:

1. Alma API URL
* The base URL for the API.
* Example: [https://api-na.hosted.exlibrisgroup.com/almaws/v1/]()

2. Alma API Key
* Your secret API key from the Ex Libris Developer Network.

3. Field to Perform Lookup With
* The ILLiad table and column containing the barcode.
* Example: Transaction.ItemInfo1

4. ILL Request User ID
* The Alma User ID (Primary ID) that the hold should be placed for like a ILL patron/user.

5. Pickup Library Code
* The code of the library where the item should be routed (e.g., MAIN, LAW, CIRC).
* This must match the code in Alma configuration.

---

## USAGE

The addon adds a "Hold Request" ribbon tab to the ILLiad Request Form.

1. Request Hold
* Reads the barcode from the transaction (ItemInfo1) field.
* Locates the item in Alma.
* Places a hold request for the configured "ILL Request User ID".
* On success: Writes "Created [RequestID]" into the "ItemInfo5" field.


2. Check Status
* Reads the Request ID from "ItemInfo5".
* Queries Alma for the current status.
* Displays a popup (e.g., "In Process", "On Hold Shelf").
* If the request was cancelled, it will report "Inactive or Cancelled".


3. Cancel Hold
* Reads the Request ID from "ItemInfo5".
* Sends a cancellation command to Alma.
* On success: Updates "ItemInfo5" to "Cancelled [RequestID]".


---

## TROUBLESHOOTING

* "No barcode found": Ensure the "Field to Perform Lookup With" setting points to a populated field or modify Main.lua if using different field.
* * Might add as configurable in config
* "Alma Error": Read the popup message. Common errors include "Patron not active" or "Item policy prevents request".
* Data Storage: This addon exclusively uses the "ItemInfo5" field to store the Alma Request ID. Do not manually clear this field if you wish to track the status.
* * Might add as configuable in config
