shape files
===========

yaml shapes for Refract.Shape.load

file          tests                                          expected
invoice.yml   every key mirrors table spec                   same shape as the invoice map in shape test
empty.yml     empty file loads as an empty map               missing key name
broken.yml    unclosed flow list                             invalid yaml
list.yml      top level list not a map                       not a map
typed.yml     yes and no stay strings in yaml 1.2            invalid value header columns rate 1.0
              1.0 is a float not an alias
sparse.yml    optional keys left empty load as null          same shape as the minimal ids map
