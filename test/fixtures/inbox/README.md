inbox fixtures
==============

mixed files for Refract.Classify with shapes in shapes/

shape           columns                                       rows
invoice         sku item kg total required sku total min 3     sku integer total number
invoice_loose   sku item total required sku total             no row rules
aws_bill        account service usage_start cost              account 12 digits usage_start datetime cost number
summary         sku total                                     sku integer total number
invoice_au      as invoice markers file au content tax invoice  sku integer total number
invoice_nz      as invoice markers file nz content gst invoice  sku integer total number

file                     tests                                         expected
invoice.csv              exact columns                                 match invoice score 1.0
invoice_renamed.csv      every column renamed via aliases              match invoice
quoted_header.csv        header cells wrapped in literal quotes        match invoice
invoice_short.csv        kg missing 3 of 4 columns                     match invoice score 0.75
invoice_semicolon.csv    semicolon separated                           match invoice with separator
bad_rows.csv             invoice header over rows failing every rule   unknown rows failed closest invoice score 0.0
stock_list.csv           shares sku and item only                      unknown no header closest invoice missing total
aws_bill.csv             aws cost and usage columns                    match aws bill
unknown.csv              unrelated columns                             unknown no header no closest shape
header_only.csv          invoice header no rows                        match invoice on the header alone rows empty
empty.csv                empty file                                    unknown no header no closest shape
messy_invoice.csv        copy of layouts messy invoice                 match invoice header row 10
                         title block above subtotal row inside         rows 11 to 14 row 13 fails score 0.75
bad_table_then_good.csv  invoice header over failing rows then a     match invoice header row 5
                         blank then the same header over good rows    best line is the best score not the first
summary_then_invoice.csv summary table then invoice table             best ambiguous both 1.0
                                                                      first picks summary at row 1
acme_au.csv              tax invoice title au in the name             invoice au by markers file and content
acme_nz.csv              gst invoice footer after the table           invoice nz by markers file and content
acme_q3.csv              tax invoice title neutral name                invoice au by the content marker alone
acme_plain.csv           no title no name hint                        ambiguous invoice au and invoice nz
invoice vs invoice_loose both score 1.0 on invoice.csv                 invoice by most columns on the same header
