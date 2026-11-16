# Refract

Refract is a swiss army knife for working with all kinds of tabular data, from clean to messy. 

At its core, it has been designed to solve common problems that you might face with CSV files (think both machine generated, streamable formats through to hideous, 'table inside a table' invoice style formats). As everything resolves to rows of key -> value pairs, plugins can bring most of the same features to other formats (XLSX, JSON, <your custom format>).

Each one of the features can be used on its own, or work together to build complex data pipelines.

- [**Read**](#read)
  - [Stream](#stream): stream any file as lazy row maps, including separator detection and encoding/BOM issues handled for you.
- [**Write**](#write)
  - [Files](#files): write rows to one file or many, with optional chunking.
- [**Find**](#find)
  - [Locate](#locate): find a table by its column names, wherever it sits in a messy/unordered file.
  - [Grid](#grid): read small form-esque files by cell position or by the label next to a value.
- [**Know what a file is**](#know-what-a-file-is)
  - [Shapes](#shapes): describe/fingerprint a known table: its columns, their aliases, its row rules.
  - [Classify](#classify): say which shape an unknown file is, or why it isnt one. Works on a single file or across a whole folder at once.
  - [Suggest](#suggest): propose how a new sources columns map onto a shape, from their names and values.
  - [Drift](#drift): flag missing, extra and duplicated columns on every classified (known) file.
- [**Check it's acceptable**](#check-its-acceptable)
  - [Validate](#validate): validate file content against its known shapes rules, per cell and across each row, reporting issues found.
  - [Profile](#profile): collect values in a column for audit purposes, in one file or across a folder.
- [**Transform**](#transform)
  - [Rows](#rows): transform row streams: rename, fill down, group, pivot, run in parallel.
  - [Parse and clean](#parse-and-clean): turn messy cells into numbers, dates and booleans.
- [**Protect**](#protect)
  - [Privacy](#privacy): two-way pseudonymise private data (think data for demos), add consistent noise to amounts (jitter numbers stochastically), redact free text.
- [**Extend**](#extend)
  - [Query](#query): run SQL over folders of files and the tables you've found, through an engine plugin. Think querying tabular data using SQL without needing to load it into a database first. Useful for joins, aggregations, and filtering across multiple files.
  - [Plugins](#plugins): extend Refract with new file formats (XLSX, JSON already available) or query engines (DuckDB available)

Note: Refract started as a port of the `Cure` project (https://www.github.com/williamthom-as/cure) to the Elixir ecosystem. It now offers major QoL improvements over the original, and Cure's original golden files run as tests here.

```elixir
{:refract, github: "williamthom-as/refract_core", tag: "v0.1.0"}
```

---

## Read

### Stream

`bills.csv`, semicolon separated, with a byte order mark:

```
account;customer;cost;usage_date
123456789012;alice;1.50;2026-10-01
123456789013;bob;2.25;2026-10-02
```

```elixir
{:ok, rows} = Refract.CSV.stream("bills.csv")

Enum.to_list(rows)
```

| account | customer | cost | usage_date |
|---|---|---|---|
| 123456789012 | alice | 1.50 | 2026-10-01 |
| 123456789013 | bob | 2.25 | 2026-10-02 |

Rows are lazy, so it can handle huge file streams in constant memory. Any reader takes a path `{:string, binary}` or `{:stream, chunks}`.

```elixir
Refract.CSV.facts("bills.csv")
#=> {:ok, %{encoding: :utf8, delimiter: ";", delimiter_source: :detected, bom: true, line_endings: :lf, trailing_newline: true, ...}}
```

- **encodings** - `encoding: :auto` (default) keeps every line that is valid UTF-8 and reads any other as Windows-1252, so `Renée` and `€` from an old export arrive intact, even in a file mixing both; `:utf8`, `:latin1` and `:windows_1252` force one; a UTF-16 file is `{:error, {:unsupported_encoding, :utf16}}`
- **writing for Excel** - `Refract.CSV.write(rows, path, bom: true)` starts the file with a UTF-8 BOM, so Excel shows `Renée`, not `RenÃ©e`
- **escape formulas** - follows OWASP best practise for CSV injection protection. By default, a text cell starting with `=`, `+`, `-` or `@` is written with a tab first inside quotes, so a spreadsheet never runs it. the tab stays in the data (`-12.50` too), so you must use `escape_formulas: false` when a program reads the file, leave as `true` if human read. 

---

## Write

### Files

```elixir
:ok = Refract.CSV.write(table.rows, "out/bill/october.csv", header: ["account", "customer", "cost"])
```

```
account,customer,cost
123456789012,alice,1.50
123456789013,bob,2.25
```

```elixir
{:ok, paths} = Refract.CSV.write_chunks(rows, "out/numbers/part.csv", rows_per_file: 2)
#=> {:ok, ["out/numbers/part_1.csv", "out/numbers/part_2.csv", "out/numbers/part_3.csv"]}
```

---

## Find

Find a table, or a value, wherever it sits.

### Locate

Finding content in a messy invoice export, `export.csv`:

```
Monthly bill export,,,
Generated 2026-10-05,,,
,,,
Acct No,Region,Customer,Amount
123456789012,au,alice,1.50
123456789013,nz,bob,2.25
,,,
Total,,,3.75
```

```elixir
spec =
  Refract.Table.spec(
    header: [columns: %{"account" => ["account", "acct no"], "customer" => ["customer"], "cost" => ["cost", "amount"]}],
    stop: [:blank]
  )

{:ok, table} = Refract.CSV.locate("export.csv", spec)

table.header_row
#=> 4

Enum.to_list(table.rows)
```

| account | customer | cost |
|---|---|---|
| 123456789012 | alice | 1.50 |
| 123456789013 | bob | 2.25 |

The header is found by its definition, columns come back under the supplied names and the table ends at the blank line.

### Grid

Small, form-esqe files, read by position or by label. `invoice_form.csv`:

```
Tax Invoice,,
Invoice No,INV-42,
Date,2026-10-05,
,,
Bill To,,
Acme Pty Ltd,,
1 Main St,,
,,
sku,item,total
78632478,apple,3.50
```

```elixir
{:ok, grid} = Refract.CSV.load("invoice_form.csv")

Refract.Grid.value(grid, label: "invoice no")
#=> "INV-42"

Refract.Grid.block(grid, after: "bill to")
#=> ["Acme Pty Ltd", "1 Main St"]

Refract.Grid.cell(grid, "B3")
#=> "2026-10-05"

line_spec = Refract.Table.spec(header: [columns: %{"sku" => ["sku"], "item" => ["item"], "total" => ["total"]}])
{:ok, lines} = Refract.Grid.locate(grid, line_spec)

Enum.to_list(lines.rows)
#=> [%{"sku" => "78632478", "item" => "apple", "total" => "3.50"}]

{:ok, result} = Refract.Grid.validate(grid, invoice)
```

`Grid.validate` works as [`CSV.validate`](#validate) does, issue lines are lines in the grid.

---

## Know what a file is

Describe each kind of file once, then recognise it.

### Shapes

A shape is a named table spec: columns with aliases, what makes it that shape, how its rows look. Either in YAML or Elixir, see below:

```yaml
# shapes/bill.yml
name: bill
header:
  columns:
    account: [account, acct no]
    customer: [customer, client]
    cost: [cost, amount]
    usage_date: [usage_date, date]
  required: [account, cost]
  min_matches: 2
row:
  match:
    account: /^\d{12}$/
    cost: number
stop: [blank]
```

```elixir
bill = Refract.Shape.load!("shapes/bill.yml")
```

Or in Elixir:

```elixir
bill =
  Refract.Shape.new(
    name: "bill",
    spec:
      Refract.Table.spec(
        header: [
          columns: %{
            "account" => ["account", "acct no"],
            "customer" => ["customer", "client"],
            "cost" => ["cost", "amount"],
            "usage_date" => ["usage_date", "date"]
          },
          required: ["account", "cost"],
          min_matches: 2
        ],
        row: [match: %{"account" => ~r/^\d{12}$/, "cost" => :number}],
        stop: [:blank]
      )
  )
```

- **aliases** - every spelling a source uses (first listed wins if file holds two or more of them)
- **`required` / `min_matches`** - mandatory of what a header needs to be this shape
- **row rules** - `integer`, `number`, `date`, `datetime`, a regex, or a function
- **markers** - `file:` and `content:` regexes that break a tie between lookalike shapes

### Classify

```elixir
shapes = [Refract.Shape.load!("shapes/bill.yml"), Refract.Shape.load!("shapes/invoice.yml")]

{:ok, result} = Refract.CSV.classify("export.csv", shapes)

{result.verdict, result.shape.name, result.file.above_header}
#=> {:match, "bill", 3}
```

A whole folder, every file read by the reader its extension asks for:

```elixir
{:ok, results} = Refract.Classify.folder("inbox", shapes)
```

| file | result |
|---|---|
| invoice.csv | `{:ok, %Result{verdict: :match, shape: invoice}}` |
| mystery.csv | `{:ok, %Result{verdict: :unknown, reason: :no_header}}` |
| notes.txt | `{:error, {:unsupported, "txt"}}` |
| october.csv | `{:ok, %Result{verdict: :match, shape: bill}}` |

- **verdicts** - `:match`, `:ambiguous` (two shapes fit), `:unknown` with a reason (`:no_header`, `:rows_failed`) and the closest shape
- **why** - every shape is a ranked candidate with its header and row reports
- **cheap and fast** - only the first 100 lines are read, so file size does not matter

### Suggest

A new source names and orders the same columns its own way, so it comes back `:unknown`. `new_source.csv`:

```
Billing export
Customer Name,Acct Number,Date Used,Total Spend
alice,123456789012,2026-10-03,4.00
bob,123456789013,2026-10-04,0.75
```

```elixir
{:ok, report} = Refract.CSV.suggest("new_source.csv", bill)

{report.row, report.passed}
#=> {2, true}
```

| column | cell | via | score | rows passing |
|---|---|---|---|---|
| account | Acct Number | `:values` | 0.4 | 2 of 2 |
| cost | Total Spend | `:values` | 0.4 | 2 of 2 |
| customer | Customer Name | `:tokens` | 0.7 | |
| usage_date | Date Used | `:tokens` | 0.7 | |

- **via** - `:alias`, `:normalised` (`accountId` = `account_id`), `:tokens` (holds every word of a name), `:fuzzy` (a typo), `:values` (no name fits, but it is the only column whose values pass the row rule)
- **one to one** - 12 digit ids pass both the `account` regex and `cost`'s `number`, but go to `account` only
- **nothing is applied** - add the cells as aliases to the shape and the source matches from then on

### Drift

Classify result says how the file is different from the provided shape. `drifting.csv`:

```
Account,Customer,Amount,Cost,Region
123456789012,alice,1.50,1.50,au
```

```elixir
{:ok, result} = Refract.CSV.classify("drifting.csv", [bill])

result.drift
#=> %Refract.Classify.Drift{
#=>   missing: ["usage_date"],
#=>   extra: [{4, "Region"}],
#=>   others: %{"cost" => [{2, "Amount"}]}
#=> }
```

- **missing** - missing columns
- **extra** - additional columns, with their index and name
- **others** - a column more than one cell matched: `Cost` won (first in the shape), `Amount` lost
- **ignore** - cells an export always has but the shape does not map: `header: [ignore: [~r/^cost centre \d+$/i, "notes"]]` keeps them out of `extra`

---

## Check it's acceptable

### Validate

Validate says whether its content is acceptable for that shape (which can be derived from `classify`). The same shape holds both: `row:` recognises the table (loose, so bad content does not stop a file being recognised), `validation:` accepts its content (strict, every row checked).

`acme_invoice_0413.csv`:

```
ACME PTY LTD - Tax Invoice,,,,
Invoice No,INV-1002,,,
ABN,51 824 753 557,,,
SKU,Description,Qty,Unit Price,Line Total
A-100,widget,2,12.50,25.00
C-300,press,1,12500.00,12500.00
B-200,gadget,4,99.00,369.00
x-1,bolt,,0.50,0.50
,,,,
Total,,,,12984.50
```

```elixir
invoice =
  Refract.Shape.new(
    name: "acme_invoice",
    spec:
      Refract.Table.spec(
        header: [
          columns: %{
            "sku" => ["sku"],
            "description" => ["description"],
            "qty" => ["qty"],
            "unit_price" => ["unit price"],
            "line_total" => ["line total"]
          },
          required: ["sku", "line_total"]
        ],
        row: [match: %{"line_total" => :number}],
        stop: [:blank]
      ),
    validation: [
      columns: %{
        "sku" => [:required, ~r/^[A-Z]-\d{3}$/],
        "qty" => [:required, :integer, {:min, 1}],
        "line_total" => [:required, :number, {:max, 10_000}]
      },
      rows: [{:line_total_adds_up, &line_total_adds_up?/1}]
    ]
  )

{:ok, result} = Refract.CSV.validate("acme_invoice_0413.csv", invoice, values: true)

result
#=> %Refract.Validate.Result{
#=>   valid: false,
#=>   rows: 4,
#=>   issues: [
#=>     %Refract.Validate.Issue{line: 6, column: "line_total", rule: {:max, 10_000}, value: "12500.00"},
#=>     %Refract.Validate.Issue{line: 7, column: nil, rule: :line_total_adds_up, value: nil},
#=>     %Refract.Validate.Issue{line: 8, column: "qty", rule: :required, value: ""},
#=>     %Refract.Validate.Issue{line: 8, column: "sku", rule: ~r/^[A-Z]-\d{3}$/, value: "x-1"},
#=>     %Refract.Validate.Issue{line: 8, column: nil, rule: :line_total_adds_up, value: nil}
#=>   ]
#=> }
```

`line_total_adds_up?/1` (custom fun) runs on each row verifying qty times unit price equals the line total.

| line | column | rule | value | why |
|---|---|---|---|---|
| 6 | line_total | `{:max, 10_000}` | `12500.00` | over the 10,000 limit |
| 7 | | `:line_total_adds_up` | | 4 x 99.00 is 396.00, the line says 369.00 |
| 8 | qty | `:required` | `""` | qty is blank |
| 8 | sku | `~r/^[A-Z]-\d{3}$/` | `x-1` | not a capital letter, a dash and three digits |
| 8 | | `:line_total_adds_up` | | with no qty the line cannot add up |

- **column rules** - `:required`, `:integer`, `:number`, `:date`, `:datetime`, a regex, `{:min, n}` / `{:max, n}` (inclusive) / `{:above, n}` / `{:below, n}` (strict; numbers in any form, or dates), `{:in, values}`, a named function `{:name, fun}`, a [validator module](#custom-validators); a column reports its first failing rule; a blank cell fails only `:required`
- **row rules** - named functions over the whole row (reported by name)
- **lines** - issues report the line in the file, failures are reported and the rows after it are still checked
- **values** - issues carry no cell values unless `values: true`

Rows already in a pipeline, split good from bad:

```elixir
{good, bad} =
  table.rows
  |> Refract.Validate.rows(invoice)
  |> Enum.split_with(&match?({:ok, _row}, &1))
```

In YAML, column rules go under `validation:` (row rules are Elixir only):

```yaml
validation:
  columns:
    sku: [required, /^[A-Z]-\d{3}$/]
    qty: [required, integer, {min: 1}]
    line_total: [required, number, {max: 10000}]
```

#### Fields (around the table)

Not all tabular formats are tidy, some have fields inside the file, above or below the content/table.

Use fields to read/validate them.

`acme_invoice_0413.csv` as a grid:

| | A | B | C | D | E |
|---|---|---|---|---|---|
| **1** | ACME PTY LTD - Tax Invoice | | | | |
| **2** | **Invoice No** | INV-1002 | | | |
| **3** | ABN | 51 824 753 557 | | | |
| **4** | SKU | Description | Qty | Unit Price | Line Total |
| **5** | A-100 | widget | 2 | 12.50 | 25.00 |
| **6** | C-300 | press | 1 | 12500.00 | 12500.00 |
| **7** | B-200 | gadget | 4 | 99.00 | 369.00 |
| **8** | x-1 | bolt | | 0.50 | 0.50 |
| **9** | | | | | |
| **10** | **Total** | | | | 12984.50 |

The table is lines 4 to 8 (found by its header). The invoice number sits right of its label (ln 2), the total right of its label on (ln 10), and there is a missing invoice date field.

```elixir
invoice =
  Refract.Shape.new(
    name: "acme_invoice",
    spec: Refract.Table.spec(...),
    validation: [...],
    fields: %{
      "invoice_no" => [label: "invoice no", rules: [:required, ~r/^INV-\d+$/]],
      "issued_on" => [label: "invoice date", rules: [:required, :date]],
      "total" => [label: "total", rules: [:required, :number]]
    }
  )

Refract.CSV.fields("acme_invoice_0413.csv", invoice)
#=> {:ok, %{"invoice_no" => "INV-1002", "issued_on" => nil, "total" => "12984.50"}}

{:ok, result} = Refract.CSV.validate("acme_invoice_0413.csv", invoice)

result.fields
#=> %{"invoice_no" => "INV-1002", "issued_on" => nil, "total" => "12984.50"}

hd(result.issues)
#=> %Refract.Validate.Issue{field: "issued_on", rule: :required, line: nil}
```

- **find content by** - `label:` (the cell right (or `take: :below`) of the label, can be a string or a regex) or `at: "B2"` (spreadsheet style cell reference).
- **rules** - the same rules as columns, a field breaking one is an issue with `field:` and its labels line (nil when the label is missing, as here: this invoice has no date)
- **reading only** - `fields/3` on any reader, `Refract.Grid.fields(grid, shape)` on a loaded grid
- **memory** - a shape with fields is validated on the whole file in memory (forms are small, `max_bytes:` guards it)

#### Document rules

Some checks need to look at the whole file to know if it is valid. `acme_invoice_0413.csv` says its total is 12,984.50, but its line totals add up to 12,894.50. This is not something that could be observed by a column or row rule, the total sits outside the table and the sum spans every row.

```elixir
total_matches_lines = fn %{fields: %{"total" => total}, rows: rows} ->
  rows
  |> Enum.map(&Refract.Parse.number!(&1["line_total"]))
  |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  |> Decimal.eq?(Refract.Parse.number!(total))
end

invoice =
  Refract.Shape.new(
    name: "acme_invoice",
    spec: Refract.Table.spec(...),
    validation: [
      columns: %{...},
      document: [{:total_matches_lines, total_matches_lines}]
    ],
    fields: %{"total" => [label: "total", rules: [:required, :number]]}
  )

{:ok, result} = Refract.CSV.validate("acme_invoice_0413.csv", invoice)

List.last(result.issues)
#=> %Refract.Validate.Issue{rule: :total_matches_lines, line: nil, column: nil, field: nil}
```

- **input** - a map with `fields` (the field values) and `rows` (every row in table)
- **result** - return true to pass; false or a raise adds an issue named after the rule, with no line
- **always runs** - doc checks are run last, and will always run even if previous failures
- **whole file** - the file is read into memory, like fields (use `max_bytes:` sets the limit)
- **Elixir only** - not available in YAML shapes

#### Custom validators

If the shipped validators do not satifsy yuor requirements, you can always impl your own `Refract.Validate.Validator`:

```elixir
defmodule MyApp.Validators.ABN do
  @behaviour Refract.Validate.Validator

  @weights [10, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19]

  @impl true
  def valid?(cell, _opts) do
    digits =
      cell
      |> to_string()
      |> Refract.Clean.digits()
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)

    length(digits) == 11 and checksum(digits) == 0
  end

  defp checksum([first | rest]) do
    [first - 1 | rest]
    |> Enum.zip(@weights)
    |> Enum.map(fn {digit, weight} -> digit * weight end)
    |> Enum.sum()
    |> rem(89)
  end
end
```

The supplier ABN on line 3 of `acme_invoice_0413.csv` fails its checksum:

```elixir
invoice =
  Refract.Shape.new(
    name: "acme_invoice",
    spec: Refract.Table.spec(...),
    fields: %{"supplier_abn" => [label: "abn", rules: [:required, MyApp.Validators.ABN]]}
  )

{:ok, result} = Refract.CSV.validate("acme_invoice_0413.csv", invoice)

hd(result.issues)
#=> %Refract.Validate.Issue{field: "supplier_abn", rule: MyApp.Validators.ABN, line: 3}
```

In YAML, name validators are available through a registry, passed at load time:

```yaml
fields:
  supplier_abn:
    label: abn
    rules: [required, abn]
```

```elixir
Refract.Shape.load!("shapes/acme_invoice.yml", validators: %{"abn" => MyApp.Validators.ABN})
```

- **options** - `{abn: {strict: true}}` arrives as `[strict: true]` (option names the validator uses)
- **names** - an unregistered name is `{:invalid_value, {"fields.supplier_abn.rules", "abn"}}`; a registry name cannot shadow a built in rule (`number` always means number); registered names work in `validation:` and `fields:`, not in `row:`

#### A folder: classify then validate

Each kind of file is one shape (one module), csv or xlsx alike. Classify the folder, validate every match:

```elixir
{:ok, results} = Refract.Classify.folder("inbox", formats, readers: [Refract.XLSX, Refract.CSV])

Enum.each(results, fn
  {path, {:ok, %{verdict: :match} = result}} ->
    {reader, opts} = result.reader
    {:ok, validation} = reader.validate(path, result.shape, opts)

    if validation.valid,
      do: accept(path, result),
      else: needs_human(path, validation.issues)

  {path, other} ->
    needs_human(path, other)
end)
```

| file | shape | outcome |
|---|---|---|
| acme_0412.csv | acme_invoice | accepted |
| acme_0413.csv | acme_invoice | needs a person: line 5 `line_total` over the limit, line 6 does not add up |
| globex_nov.csv | globex_usage | needs a person: line 2 `account` is not 12 digits |
| globex_oct.csv | globex_usage | accepted |
| notes.csv | | needs a person: `:unknown`, no shape fits |

- **`:unknown`** - a new kind of file: [`suggest`](#suggest) its mapping, then write one module
- **`:ambiguous`** - two shapes fit: give one a marker
- **drift** on a match - missing, extra or duplicated columns ([Drift](#drift))
- **`validation.issues`** - the line, column and rule that failed

### Profile

A file can pass validation and still spell one value many ways. Profile reports them per column, so the source can be fixed and reexported. `ledger_oct.csv`:

```
Account,Cost Centre,Amount
A-100,Cost Center 1,120.00
A-101,costcenter1,45.50
A-102,Cost Centre 1,12.00
A-103,Cost Center 1,8.25
A-104,Cost Center 2,99.00
A-105,Cost Center 2 ,15.00
```

```elixir
{:ok, result} = Refract.CSV.profile("ledger_oct.csv", ledger)

Refract.CSV.write(Refract.Profile.rows(result), "ledger_oct_profile.csv", header: Refract.Profile.header())
```

| column | most_common | via | variant | count | lines |
|---|---|---|---|---|---|
| cost_centre | Cost Center 1 | fuzzy | Cost Center 1 | 2 | 2, 5 |
| cost_centre | Cost Center 1 | fuzzy | costcenter1 | 1 | 3 |
| cost_centre | Cost Center 1 | fuzzy | Cost Centre 1 | 1 | 4 |
| cost_centre | Cost Center 2 | normalised | Cost Center 2 | 1 | 6 |
| cost_centre | Cost Center 2 | normalised | "Cost Center 2 " | 1 | 7 |

- **via** - `:normalised` (equal once case, spacing, punctuation and accents are ignored), `:fuzzy` (a typo of the most common spelling, worth a look)
- **digits** - values with different numbers never group: `Cost Center 1` and `Cost Center 2` stay apart
- **invisible differences** - a trailing space or a non breaking space is shown quoted
- **every column** - typed or not; `except: ["notes"]` leaves columns out; `columns: :all` also profiles header cells the shape does not name (under their header text)
- **values** - `values: true` lists every distinct value with its count and lines, an inventory of the column to check that everything belongs: `Refract.Profile.rows(result, :values)` with `header: Refract.Profile.header(:values)`
- **fuzzy** - `fuzzy: 0.9` groups looser typos, `fuzzy: false` turns it off (short codes, part numbers); a folder takes `%{"ledger" => 0.9, "parts" => false}`
- **folder** - `Refract.Profile.folder("inbox", [ledger])` counts every file a shape matched as one, so `costcenter1` in one month and `Cost Center 1` in the next show up together, lines by file
- **read only** - nothing is changed; lines are file lines

---

## Transform

Reshape rows and clean their cells.

### Rows

Lazy transforms over row maps

| Acct | Customer | Month | Cost |
|---|---|---|---|
| 123456789012 | alice | jul | $1.50 |
| 123456789012 | | aug | $2.00 |
| 123456789013 | bob | jul | $0.75 |
| 123456789013 | | aug | |

```elixir
cleaned =
  rows
  |> Refract.Rows.select(%{"Acct" => "account", "Customer" => "customer", "Month" => "month", "Cost" => "cost"})
  |> Refract.Rows.fill_down("customer")
  |> Refract.Rows.update("cost", &Refract.Parse.number!(&1, currency: true), skip_blank: true)
```

| account | customer | month | cost |
|---|---|---|---|
| 123456789012 | alice | jul | 1.50 |
| 123456789012 | alice | aug | 2.00 |
| 123456789013 | bob | jul | 0.75 |
| 123456789013 | bob | aug | |

```elixir
Refract.Rows.pivot(cleaned, by: "account", key: "month", value: "cost", columns: ["jul", "aug"])
```

| account | jul | aug |
|---|---|---|
| 123456789012 | 1.50 | 2.00 |
| 123456789013 | 0.75 | |

Also `put`, `copy`, `rename`, `drop`, `take`, `distinct`, `reject_blank`, `from` / `until`, `group`, and `parallel` to run a pipeline across cores with order kept.

### Parse and clean

```elixir
Refract.Parse.number("$1,234.50", currency: true)            #=> {:ok, Decimal.new("1234.50")}
Refract.Parse.number("1.234,56", locale: :de)                #=> {:ok, Decimal.new("1234.56")}
Refract.Parse.number("(12.00)", currency: true)              #=> {:ok, Decimal.new("-12.00")}
Refract.Parse.number("n/a")                                  #=> {:error, {:not_a_number, "n/a"}}
Refract.Parse.date("02-Oct-2026", formats: ["dd-MMM-yyyy"])  #=> {:ok, ~D[2026-10-02]}
Refract.Parse.date("05/10/2026", formats: [:dmy])            #=> {:ok, ~D[2026-10-05]}
Refract.Parse.date("08/01/25", formats: ["dd/MM/20yy"])      #=> {:ok, ~D[2025-01-08]}
Refract.Parse.boolean("Yes")                                 #=> {:ok, true}

Refract.Clean.normalise_whitespace("  big   red\tapple ")     #=> "big red apple"
Refract.Clean.slug("Lean Meat Yield (%)")                    #=> "lean_meat_yield"
Refract.Clean.digits("+61 (0)4 1234-5678")                   #=> "610412345678"
```

Every parser has a bang version.

---

## Protect

### Privacy

Good for demo data, or for adding noise to amounts before sharing. `bills.csv`:

```elixir
keyring = Refract.Privacy.Keyring.from_provider!(Refract.Privacy.KeyProvider.Env, [])

{:ok, rows} = Refract.CSV.stream("bills.csv")

rows
|> Refract.Rows.update("cost", fn cost, ctx ->
  Refract.Privacy.Noise.relative(Refract.Parse.number!(cost), 0.05, seed: ctx.row["account"], domain: :cost, keyring: keyring)
end)
|> Refract.Rows.update("account", &Refract.Privacy.Pseudonym.apply!(&1, :account, keyring))
|> Refract.Rows.update("customer", &Refract.Privacy.Redact.mask(&1, keep_first: 1))
```

| account | customer | cost | usage_date |
|---|---|---|---|
| 735034101269 | a**** | 1.45 | 2026-10-01 |
| 849877448529 | b** | 2.27 | 2026-10-02 |

```elixir
Refract.Privacy.Pseudonym.reverse!("735034101269", :account, keyring)
#=> "123456789012"
```

| tool | reversible | keeps format | use for |
|---|---|---|---|
| `Pseudonym` (FF1) | yes, with the key | yes | ids that must still join |
| `Noise` | no | number type | amounts, counts |
| `Gen` | no | chosen | stable fake ids |
| `Redact` | no | length (`mask`) | names, free text |

Keys come from `REFRACT_KEY_1`, `REFRACT_KEY_2`, ... (versioned, rotate by adding one), one derived key per domain.

Refract's FF1 and keyed pseudonyms have not been independently audited. Use them for demo, test and shared sample data, not as compliance grade anonymisation. Anyone holding the key can reverse a pseudonym.

---

## Extend

Add engines and file formats.

### Query

With an engine plugin (`refract_duckdb`), every folder of files is a table, and any rows can be loaded beside them:

```elixir
query = Refract.Query.open!(engine: Refract.Query.DuckDB)

{:ok, ["bill"]} = Refract.Query.views(query, "out")

customers = [%{"customer" => "alice", "plan" => "pro"}, %{"customer" => "bob", "plan" => "free"}]
:ok = Refract.Query.table(query, "customers", customers, columns: ["customer", "plan"])

result =
  Refract.Query.run!(query, """
  SELECT c.plan, sum(CAST(b.cost AS DECIMAL(18, 2))) AS cost
  FROM bill b JOIN customers c USING (customer)
  GROUP BY c.plan ORDER BY c.plan
  """)

:ok = Refract.CSV.write(result.rows, "plan_costs.csv", header: result.columns)
```

| plan | cost |
|---|---|
| free | 2.25 |
| pro | 1.50 |

- **views** - one per folder, every file in it, columns joined by name, read as text so ids keep their leading zeros
- **params** - `Refract.Query.run!(query, "SELECT customer FROM bill WHERE account = $1", ["123456789013"])`
- **results** - a lazy stream of maps, columns in select order

### Plugins

Every reader (built in or via plugin) has the same functions: `stream`, `locate`, `classify`, `suggest`, `validate`, `profile`, `fields`, `facts` and `load`. Its own options pass straight through.

| reader | files | impl options |
|---|---|---|
| `Refract.CSV` (built in) | `.csv`, `.tsv` | `separator:` (detected by default), `encoding:` (`:auto` by default) |
| `Refract.XLSX` (`refract_xlsx`) | `.xlsx`, `.xlsm` | `sheet:` (a name or a position), `hidden:` |
| `Refract.JSON` (`refract_json`) | `.json` | `at:`, `keyed:`, `unnest:`, `keep:` |
| `Refract.JSONL` (`refract_json`) | `.jsonl`, `.ndjson` | `scan:`, `columns:`, `unnest:`, `keep:` |

```elixir
Refract.XLSX.suggest("new_source.xlsx", bill, sheet: "Billing")
Refract.JSON.validate("export.json", bill, at: ["data"])
Refract.Classify.folder("inbox", shapes, readers: [Refract.XLSX, Refract.JSON, Refract.JSONL])
```

Writers are the same, all with `write` and `write_chunks`; `Refract.CSV` also takes `bom: true`, `Refract.XLSX` takes `sheet:`.

**`refract_xlsx`** - workbooks, one sheet at a time (cells are typed):

```elixir
:ok = Refract.XLSX.write(rows, "bills.xlsx", sheet: "Oct", header: ["account", "cost", "usage_date"])

{:ok, rows} = Refract.XLSX.stream("bills.xlsx", sheet: "Oct")
#=> [%{"account" => "123456789012", "cost" => Decimal.new("1.50"), "usage_date" => ~D[2026-10-01]}]

{:ok, sheets} = Refract.XLSX.classify_sheets("q3.xlsx", shapes)
```

**`refract_json`** - JSON and JSONL

```json
{"data": [{"id": 7, "customer": {"id": 2}, "lines": [{"sku": "A1", "qty": 3}, {"sku": "B2", "qty": 1}]},
          {"id": 8, "customer": {"id": 5}, "lines": [{"sku": "A1", "qty": 2}]}],
 "next": null}
```

```elixir
{:ok, orders} = Refract.JSON.stream(page, at: ["data"])
{:ok, lines} = Refract.JSON.stream(page, at: ["data"], unnest: ["lines"], keep: %{"order_id" => "id"})
```

| id | customer.id | lines |
|---|---|---|
| 7 | 2 | `[{"sku":"A1","qty":3},{"sku":"B2","qty":1}]` |
| 8 | 5 | `[{"sku":"A1","qty":2}]` |

| order_id | sku | qty |
|---|---|---|
| 7 | A1 | 3 |
| 7 | B2 | 1 |
| 8 | A1 | 2 |

**`refract_duckdb`** - the query engine behind [Query](#query).

Your own reader, writer or engine: implement `Refract.Reader`, `Refract.Writer` or `Refract.Query.Engine`, and check it with `Refract.Test.ReaderCase`, `WriterCase` or `EngineCase`.

## License

Apache-2.0, see [LICENSE](LICENSE).
