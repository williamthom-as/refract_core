shape fixtures m2
=================

row numbers 1 based as in explain

file                    tests                                               expected
messy_invoice           header shifted to col 1 address block subtotal      header row 10
                        row inside table footer total                       columns vendor 1 sku 3 item 4 cost per kg 5 kg 6 total 7
                                                                            3 rows row 13 subtotal skipped 1 miss used stop at blank row 15
messy_invoice_renamed   vendor renamed headers supplier product code        same table as messy invoice via aliases
                        description unit price qty amount
messy_invoice_decoy     row 6 has sku and total like words not a header     decoy below required and min matches real header row 10
no_table                metadata only no table                              header not found with closest row and what it lacked
repeated_header         header repeated mid table pdf export style          mvp blank plus repeat stop table 2 rows
                                                                            post mvp repeat skip continues 3 rows

anchors grid mode on messy_invoice
value label invoice no take right gives INV-0042
value label date take right gives 2010-01-01
value label invoice total take right gives 17 5
block after bill to until blank gives lean davis and 4 farm rd orange
