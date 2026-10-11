nasty csv fixtures
==================

raw means bare nimble csv 1 3 0 rfc4180 parse stream line mode
open means not decided yet

file                        hazard                                  raw                              refract
quoted_newline              newline inside quoted field             ok                               same
quoted_newline_crlf         crlf inside quoted field                embedded crlf becomes lf         open keep normalised or preserve crlf
escaped_quotes              double quote escapes                    ok                               same
comma_in_quoted             separator inside quotes                 ok                               same
bom                         utf8 bom                                bom kept in first header         bom stripped
crlf                        crlf line endings                       ok cr removed                    same
no_trailing_newline         last line without newline               ok                               same
unicode                     accents cjk 4 byte cjk combining char   ok bytes preserved               same no unicode normalisation
trailing_empty_columns      trailing empty headers and cells        empty strings                    headers id name col 2 col 3 cells kept
blank_headers               whitespace only and empty header        space and empty string           headers id col 1 name col 3
duplicate_headers           repeated and case different headers     as is                            id name name 2 Name case sensitive
quoted_headers              padded and quote wrapped headers        as is                            Name Qty Price
header_only                 header no data                          header row only                  empty stream table header id name
empty                       zero bytes                              no rows                          stream empty locate header not found nil
blank_lines_inside          empty lines between rows                each blank line one empty cell   open keep as blank rows or drop
ragged_rows                 short row and long row                  as is                            open short pad nil long error drop or extra key
semicolon                   semicolon separator comma decimal       ok with semicolon parser         same via separator
tab                         tab separator quoted tab                ok with tab parser               same via separator
stray_quote                 quote mid field not rfc4180             raises parse error               default error with line number liberal later accepts
mixed_line_endings          crlf and lf in one file                 ok                               facts line endings mixed crlf 2 lf 1
cr_only                     old mac cr line endings                 one line                         facts line endings cr parsing not supported yet
pipe                        pipe separator                          ok with pipe parser              detect finds pipe
single_column               one column no separator to find         ok                               detect falls back to comma default

reader implications
===================

bom stripping is refract
one nimble csv parser per separator defined at compile time for comma,semicolon,tab,pipe
blank lines and ragged rows arrive as is header step decides
liberal needs its own fallback nimble csv has no tolerant mode
