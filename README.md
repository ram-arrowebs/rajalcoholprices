# Alcohol Prices in Rajasthan, IN

Showcase Google Sheet **`IMPORTHTML()`** function to get alcohol prices from Rajasthan Goverment Excise Department webpage and create a responsive view.

> The data source is an HTML Table in a vast maze of nested HTML tables in https://rajexcise.gov.in/RSBCL-Price-List.aspx

Add this formula in the cell `A1` of a blank google sheet. You can learn more on how to use `IMPORTHTML()` function [here.](https://blog.coupler.io/importhtml-function-google-sheets/) 

`=importhtml("https://rajexcise.gov.in/RSBCL-Price-List.aspx", "table", 22)`

At this point, intelligent data is now available from Google Sheet which can be consumed in many ways. Here [PapaParse.js](https://www.papaparse.com/) and [Datatable.js](https://datatables.net) are used to generate a [page hosted right here on github!](https://ram-arrowebs.github.io/rajalcoholprices/)

This project has just a single file and all the scripts are referenced from publicly avaiable CDNs.

#### Data (and the issues therein)

The header with wrapped content on the header of the last column forced ignoring the header altogether and the column with the serial numbering is of no use either.

`https://docs.google.com/spreadsheets/d/`**`[GOOGLE_SHEETS_ID]`**`/gviz/tq?tqx=out:csv&sheet=data&range=`**`B2:D`**

#### PapaParse and Datatable

Datatable is used as presentation layer and the PapaParse fetches data from Google Sheets CSV output, converts into JSON and feeds into Datatable. All in a single line of code

    Papa.parse(google_sheet_csv, {
        download: true,
        complete: function(results) {           
            $('#DataTable').DataTable({
                "data": results.data
            });
        }
    });

With a little bit of styling for alignment and clutter;

https://ram-arrowebs.github.io/rajalcoholprices/

#### Next Steps

Create a manifest to make this a PWA with an ability to add it to Home Screen!
