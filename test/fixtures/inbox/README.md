inbox fixtures p1
=================

mixed files for Refract.Classify with shapes in shapes/

shape           columns                                       rows
invoice         sku item kg total required sku total min 3     sku integer total number
invoice_loose   sku item total required sku total             no row rules
aws_bill        account service usage_start cost              account 12 digits usage_start datetime cost number

file                     tests                                         expected
invoice.csv              exact columns                                 match invoice score 1.0
invoice_renamed.csv      every column renamed via aliases              match invoice
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
invoice vs invoice_loose both score 1.0 on invoice.csv                 ambiguous within margin
