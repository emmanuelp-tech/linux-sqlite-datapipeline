# linux-sqlite-datapipeline
Linux-based data pipeline using shell tools for CSV cleaning, aggregation, SQLite storage, and local Streamlit visualization.


# Steam Games Dataset — Linux-First Data Pipeline Documentation

## Table of Contents

1.  [Project Overview](#project-overview)
2.  [Basic Commands](#basic-commands)
3.  [Data Cleaning](#data-cleaning)
    - [CSV Preprocessing: Comma Replacement](#csv-preprocessing-comma-replacement)
    - [Missing Value Detection](#missing-value-detection)
    - [Row-Level Data Cleaning](#row-level-data-cleaning)
4.  [Data Validation](#data-validation)
    - [Schema Validation](#schema-validation)
5.  [Data Analysis](#data-analysis)
    - [Single-Pass Data Aggregation](#single-pass-data-aggregation)
    - [Additional Aggregation Passes](#additional-aggregation-passes)

* * *

## Project Overview

This notebook accompanies a **Linux shell–based data pipeline** built for analyzing a real-world Steam games dataset from Kaggle. Instead of using pandas for the entire workflow, this project deliberately focuses on **Unix command-line tools** (`awk`, `sed`, `cut`, `sort`, `uniq`, `perl`) for data cleaning and aggregation, with results stored in **SQLite** and visualized locally using **Streamlit**.

### Project Goals

- Clean and validate a large CSV dataset using **Linux shell tools**
- Handle quoted fields, encoding issues, and missing values correctly
- Perform meaningful aggregations without loading the full dataset into memory
- Store analysis results in **SQLite** for reuse
- Visualize aggregated results using **Streamlit** (run locally)

This project was extended beyond a basic assignment to explore how **lightweight, composable tools** can be combined into a full analysis pipeline.

### What This Notebook Contains

- This notebook **does not execute the full pipeline**
- Instead, it **includes the full shell script** used to:
    - clean the dataset
    - validate missing values
    - aggregate key metrics
    - populate SQLite tables
    - launch a Streamlit dashboard locally

The Streamlit app is meant to be run **on a local machine**, not inside Kaggle.

### Pipeline Overview

**1\. Data Cleaning (Shell)**

- Replace commas inside quoted CSV fields using `perl`
- Normalize line endings
- Detect missing or invalid values across all columns
- Remove rows containing missing values

**2\. Aggregation (Shell)**

All aggregations are performed using Linux utilities:

- total number of games
- number of unique genres, categories, developers, publishers
- free vs paid games
- price distribution using custom price brackets
- game count by release year
- game count by year and month
- genre-wise and category-wise game counts

**3\. Storage (SQLite)**

Aggregated results are stored in SQLite tables such as:

- `counts`
- `price_brackets`
- `genre_counts`
- `category_counts`
- `games_by_year`
- `games_by_year_month`

This avoids recomputation and keeps the visualization layer lightweight.

**4\. Visualization (Streamlit — Local)**

A Streamlit app reads directly from SQLite and displays:

- KPI metrics
- price distribution (bucketed)
- games released per year
- top genres and categories
- monthly releases for a selected year

### Why Linux Tools?

- Transparent transformations
- Low memory overhead
- Easy to reason about and debug
- Commonly used in real data engineering pipelines
- Demonstrates understanding beyond library-only workflows

### How to Run Locally

1.  Download shell script and dataset.
2.  Grant permission for execution: `chmod +x pipeline.sh`
3.  Run: `./pipeline.sh`

**Requirements:**

- Linux (Ubuntu / KDE Neon)
- `perl`, `sqlite3`, `pipx`, `python3`
- Streamlit installed via `pipx`

### Dataset Source

This project uses the **Steam Games Dataset (2021–2025)** sourced from Kaggle.

Source: https://www.kaggle.com/datasets/jypenpen54534/steam-games-dataset-2021-2025-65k

* * *

## Basic Commands 
(for exploratory purposes)

**First few rows:**

```bash
head -n 10 steam.csv
```

**Last few rows:**

```bash
tail -n 10 steam.csv
```

**Unique rows:**

```bash
sort steam.csv | uniq | wc -l
```

(includes header row with column names, so subtract 1)

**Encoding of file:**

```bash
file -i steam.csv
```

The dataset was verified to be UTF-8 encoded using `file -i`. A UTF-8 normalisation pass was applied to ensure compatibility with shell utilities.

**Distribution of price and year:**

```bash
cut -d',' -f7 steam_clean.csv | sort -n | uniq -c | tail
cut -d',' -f3 steam_clean.csv | sort | uniq -c
```

* * *

## Data Cleaning

### CSV Preprocessing: Comma Replacement

```bash
perl -pe 's/"([^"]*)"/my $s=$1; $s=~s@,@;@g; $s/ge' steam.csv | sed 's/\r$//' > steam_temp.csv
```

**Purpose:** Replaces commas within quoted fields with semicolons to prevent parsing conflicts, while normalizing line endings for consistent database ingestion.

**Operation:**

- **Perl component** (`-pe` flags): Processes each line, executing substitution code
    - Pattern `"([^"]*)"` captures content between quotes into `$1`
    - Replacement executes: `my $s=$1; $s=~s@,@;@g; $s`
        - Stores captured text in `$s`
        - Substitutes all commas with semicolons via `s@,@;@g`
        - Returns modified string
    - Modifiers: `g` (global - all matches), `e` (evaluate replacement as code)
- **Sed component**: Strips carriage returns (`\r`) to convert CRLF to LF line endings

**Result:** Field delimiters remain intact; only intra-field commas are replaced (e.g., `"action, adventure"` becomes `"action; adventure"`)

### Missing Value Detection

```bash
awk -F',' '
NR==1 {
    for(i=1; i<=NF; i++) {
        header[i] = $i
        missing[i] = 0
    }
    max_cols = NF
    next
}
{
    for(i=1; i<=max_cols; i++) {
        if($i == "" || 
           $i ~ /^[[:space:]]*$/ || 
           $i == "NA" || 
           $i == "NaN" || 
           $i == "null" || 
           $i == "NULL" || 
           $i == "None" ||
           $i == "[]" ||
           $i == "{}" ||
           $i == "()" ||
           $i == "N/A" ||
           $i == "n/a") {
            missing[i]++
        }
    }
    total++
}
END {
    print "Total rows:", total
    print "\nMissing values per column:"
    for(i=1; i<=max_cols; i++) {
        printf "Column %d (%s): %d missing (%.2f%%)\n", i, header[i], missing[i], (missing[i]/total)*100
    }
}' steam_clean.csv
```

**Purpose:** Analyzes CSV data quality by counting missing or null values per column before database insertion.

**Operation:**

- **Field separator** (`-F','`): Splits input on commas
- **Header processing** (`NR==1`): Stores column names in `header[]` array, initializes `missing[]` counters, records total columns in `max_cols`
- **Data processing** (subsequent rows): Iterates through each column, incrementing `missing[i]` when encountering:
    - Empty strings or whitespace-only fields
    - Standard null representations: `NA`, `NaN`, `null`, `NULL`, `None`, `N/A`, `n/a`
    - Empty containers: `[]`, `{}`, `()`
- **Output** (`END` block): Reports total row count and per-column missing value counts with column names

**Result:** Data quality summary identifying columns requiring imputation or cleaning strategies prior to database ingestion.

### Row-Level Data Cleaning

```bash
awk -F',' '
NR==1 {print; next}
{
  skip=0
  for(i=1;i<=NF;i++)
    if($i=="" || $i~/^[[:space:]]*$/ || $i=="NA" || $i=="NaN" ||
       $i=="null" || $i=="NULL" || $i=="None" ||
       $i=="[]" || $i=="{}" || $i=="()" || $i=="N/A" || $i=="n/a") {
      skip=1
      break
    }
  if(!skip) print
}' steam_temp.csv > steam_script.csv

rm steam_temp.csv

final_rows=$(wc -l < steam_script.csv)
echo "✓ Final dataset: $((final_rows - 1)) rows (excluding header)"
echo "✓ Cleaned file saved: steam_script.csv"
```

**Purpose:** Removes incomplete records from the dataset by filtering out any row containing null or missing values, ensuring data integrity for database storage and analysis.

**Operation:**

- **AWK filtering**:
    - Preserves header row (`NR==1`)
    - Iterates through each field per row, checking for null patterns (identical to detection script)
    - Sets `skip=1` flag and breaks loop on first missing value encountered
    - Outputs only complete rows (where `skip` remains 0)
- **Cleanup**: Removes temporary file `steam_temp.csv`
- **Validation**: Counts final rows using `wc -l`, reports cleaned dataset size (excluding header)

**Result:** `steam_script.csv` contains only complete records suitable for reliable database operations and statistical analysis.

* * *

## Data Validation

### Schema Validation

```bash
awk -F',' '
NR==1 {next}
{
    # Column count
    if(NF!=10) invalid_cols++
    
    # appid validation
    if($1 !~ /^[0-9]+$/) invalid_appid++
    
    # release_year validation
    if($3 < 2000 || $3 > 2030) invalid_year++
    
    # price validation
    if($7 !~ /^[0-9]+(\.[0-9]+)?$/) invalid_price++
    
    # recommendations validation
    if($8 !~ /^[0-9]+$/) invalid_rec++
    
    # Store appids for uniqueness check
    appids[$1]++
}
END {
    # Output validation results...
}' steam_script.csv
```

**Purpose:** Validates data conforms to expected schema constraints before database insertion, identifying structural and type inconsistencies that could cause constraint violations or analysis errors.

**Validation Rules:**

- **Column count**: Verifies exactly 10 fields per row
- **appid** (field 1): Must be integer-only (regex `^[0-9]+$`), tracks occurrences in `appids[]` array for uniqueness verification
- **release_year** (field 3): Must fall within range 2000–2030
- **price** (field 7): Must match numeric format including decimals (regex `^[0-9]+(\.[0-9]+)?$`)
- **recommendations** (field 8): Must be integer-only

**Output:** Reports violation counts per validation rule with pass/fail indicators, enabling identification of data quality issues requiring attention before database schema enforcement.

* * *

## Data Analysis

### Single-Pass Data Aggregation

```bash
awk -F',' '
NR==1 {next}
{
    # Multiple aggregations performed simultaneously...
}
END {
    # Generate SQL INSERT statements for all computed metrics...
}' steam_script.csv | sqlite3 analysis.db
```

**Purpose:** Computes multiple statistical metrics in a single file scan, generating SQL INSERT statements piped directly to SQLite for efficient database population.

**Processing Logic:**

- **Counters:** Total games, unique developers/publishers, free vs paid splits, self-published vs external
- **Price analysis:** Categorizes into 9 brackets (Free, \$0.49–2.00, ... \$100+)
- **Temporal aggregations:** Games per year, per year-month (splits date field), price accumulation by year
- **Trend analysis:** Free-to-play percentage by year, controller support adoption by year (pattern matches field 6)
- **Genre/category parsing:** Splits delimited fields, counts individual genres and categories, tracks free games per genre
- **Indie comparison:** Separates indie titles (genre pattern match), computes average prices for indie vs non-indie

**Output:** END block formats all aggregations as INSERT statements for 10 database tables (counts, price_brackets, games_by_year, games_by_year_month, free_to_play_trend, controller_support, indie_vs_non_indie, genre_counts, category_counts, free_genres), calculating percentages using `(count/total)*100` where applicable.

**Result:** Pre-aggregated analytics tables ready for dashboard visualization without runtime SQL computations.

### Additional Aggregation Passes

#### Pass 2: Median Price by Year

```bash
awk -F',' 'NR>1 {prices[$3]=prices[$3]" "$7} END {for(y in prices) print y, prices[y]}' steam_script.csv | \
while read year prices; do
  median=$(echo "$prices" | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END {print a[int(NR/2+0.5)]}')
  echo "INSERT INTO median_price_by_year VALUES ($year, $median);"
done | sqlite3 analysis.db
```

**Purpose:** Computes median prices per year, requiring separate pass due to sorting dependency.

**Operation:**

- **AWK aggregation:** Accumulates space-separated price lists per year (field 3)
- **Shell loop:** Iterates through each year's prices
    - `tr ' ' '\n'`: Converts space-separated prices to newline-delimited list
    - `sort -n`: Numerically sorts prices
    - **Median calculation:** Stores sorted values in array `a[]`, selects middle element using index `int(NR/2+0.5)` (handles both odd/even count cases)
- Generates INSERT statements for `median_price_by_year` table

#### Pass 3: Top Genre Combinations

```bash
awk -F',' 'NR>1 {
  gsub(/;/,", ",$5)
  combos[$5]++
}
END {
  for(c in combos) print combos[c]"\t"c
}' steam_script.csv | sort -rn | head -20 | \
awk -F'\t' '{gsub(/"/,"\"\"",$2); print "INSERT INTO genre_combinations VALUES (\""$2"\"," $1 ");"}' | \
sqlite3 analysis.db
```

**Purpose:** Identifies 20 most common genre combinations for pattern analysis.

**Operation:**

- **AWK aggregation:** Replaces semicolons with commas in genre field (field 5), counts occurrences of each combination
- **Pipeline sorting:** Outputs `count\tcombination` format, sorts by count descending (`-rn`), extracts top 20
- **SQL formatting:** Second AWK escapes quotes (doubles them for SQL), constructs INSERT statements for `genre_combinations` table
