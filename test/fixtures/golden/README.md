golden files
============

all files from original cure project [github/williamthom-as/cure]

dir                  milestone   cure spec                                   files
empty_columns        m1          empty columns spec                          input expected
bad_data             m1 or m2    bad data csv spec                           input expected
total_arrivals       m3          total arrivals spec                         input expected
invoice              m3          invoice csv spec                            input expected
aws                  m4          aws csv spec                                input expected
simple_chunked       m4          simple chunked csv spec                     input only structural
simple_translations  m4          simple translations spec                    input only no assert in cure
db_testing           post mvp    db testing spec                             colors dessert dessert two structural
simple_joins         post mvp    simple joins spec and string contents spec  names ages expected
complex_joins        post mvp    complex joins spec                          names ages expected
multisheet_anon      post mvp    multisheet anon spec                        customers orders payments expected data expected lookup

input quirks
============

no trailing newline on last line in most inputs
total_arrivals input starts with utf8 bom
bad_data input has 3 empty rows above header so skip 3 or locate
invoice input headers have leading spaces trimmed by header normalisation
empty_columns expected keeps whitespace only cells
total_arrivals headers parse with literal wrapping quotes stripped by header normalisation

refract differs
===============

aws expected usage account id is 987654321 in cure due to cross column history bleed
aws refract domains do not bleed so gen digits gives keyed 10 digit value
aws expected regenerated 2026-10-04 usage account id is gen digits length 10 domain aws_account with the test keyring root 32 bytes of 1 giving 4526247778 other columns unchanged
aws output column order follows source order product code before usage type
total_arrivals expected corrected 2026-10-02 year is the year of the date in every row cure had 66 rows with a stale year from translation history bleed
total_arrivals expected corrected 2026-10-02 arrivals and difference exact for jan 2017 jul 2018 jul 2019 cure float truncation gave 2069999 for 2.07 million
total_arrivals input ends with a blank line then notes so rows stop at the first blank row

structural asserts
==================

simple_chunked 3 rows at 2 per file gives 1 default with 2 rows and 2 default with 1 row
simple_chunked test column is 12 digits test column 2 stays def
db_testing name translates identically across colors and dessert
db_testing dessert plus dessert two gives 10 rows
