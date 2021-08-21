# Alcohol Prices in Rajasthan, IN

Showcase Google Sheet **`IMPORTHTML()`** function to get alcohol prices from Rajasthan Goverment Excise Department webpage and create a responsive view.

> The data source is an HTML Table in a vast maze of nested HTML tables in https://rajexcise.gov.in/RSBCL-Price-List.aspx

Add this formula in the cell `A1` of a blank google sheet. You can learn more on how to use `IMPORTHTML()` function [here.](https://blog.coupler.io/importhtml-function-google-sheets/) 

`=importhtml("https://rajexcise.gov.in/RSBCL-Price-List.aspx", "table", 22)`

Next step is to use PapaParse to generate some nice looking page!

