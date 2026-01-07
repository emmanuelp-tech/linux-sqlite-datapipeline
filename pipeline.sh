#!/bin/bash

set -e

# -----------------------------
# 1. Install requirements
# -----------------------------
# sudo apt update
# sudo apt install -y perl sqlite3 pipx python3

pipx install streamlit || true
pipx inject streamlit pandas plotly

# -----------------------------
# 2. Clean CSV & Report Missing Values
# -----------------------------

echo "=== Step 1: Cleaning CSV ==="
perl -pe 's/"([^"]*)"/my $s=$1; $s=~s@,@;@g; $s/ge' steam.csv | sed 's/\r$//' > steam_temp.csv
echo "✓ Quotes cleaned and line endings normalized"

echo ""
echo "=== Step 2: Missing Values Report ==="
awk -F',' '
NR==1 {
    for(i=1; i<=NF; i++) { header[i]=$i; missing[i]=0 }
    max_cols=NF; next
}
{
    for(i=1;i<=max_cols;i++)
        if($i=="" || $i~/^[[:space:]]*$/ || $i=="NA" || $i=="NaN" ||
           $i=="null" || $i=="NULL" || $i=="None" ||
           $i=="[]" || $i=="{}" || $i=="()" || $i=="N/A" || $i=="n/a")
            missing[i]++
    total++
}
END{
    print "Total rows:", total
    for(i=1;i<=max_cols;i++)
        printf "Column %d (%s): %d missing\n", i, header[i], missing[i]
}' steam_temp.csv

# -----------------------------
# 3. Remove rows with missing values
# -----------------------------
echo ""
echo "=== Step 3: Removing rows with missing values ==="
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

# -----------------------------
# 4. Schema Validation
# -----------------------------
echo ""
echo "=== Step 4: Schema Validation ==="

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
    print "Column count validation:"
    if(invalid_cols > 0)
        print "  ⚠ Warning: Found " invalid_cols " rows with incorrect column count"
    else
        print "  ✓ All rows have 10 columns"

    print "appid validation:"
    if(invalid_appid > 0)
        print "  ⚠ Warning: Found " invalid_appid " non-numeric appid values"
    else
        print "  ✓ All appid values are numeric"

    print "release_year validation:"
    if(invalid_year > 0)
        print "  ⚠ Warning: Found " invalid_year " invalid year values"
    else
        print "  ✓ All release_year values are valid (2000-2030)"

    print "price validation:"
    if(invalid_price > 0)
        print "  ⚠ Warning: Found " invalid_price " non-numeric price values"
    else
        print "  ✓ All price values are numeric"

    print "recommendations validation:"
    if(invalid_rec > 0)
        print "  ⚠ Warning: Found " invalid_rec " non-numeric recommendation values"
    else
        print "  ✓ All recommendation values are numeric"

    print "appid uniqueness:"
    dup_count=0
    for(id in appids)
        if(appids[id] > 1) dup_count++
    if(dup_count > 0)
        print "  ⚠ Warning: Found " dup_count " duplicate appid values"
    else
        print "  ✓ All appid values are unique"
}' steam_script.csv

# -----------------------------
# 5. Create SQLite tables
# -----------------------------
echo ""
echo "=== Step 5: Creating SQLite database ==="
sqlite3 analysis.db <<EOF
DROP TABLE IF EXISTS counts;
CREATE TABLE counts (metric TEXT PRIMARY KEY, value INTEGER);

DROP TABLE IF EXISTS price_brackets;
CREATE TABLE price_brackets (price_range TEXT, game_count INTEGER);

DROP TABLE IF EXISTS genre_counts;
CREATE TABLE genre_counts (genre TEXT, game_count INTEGER);

DROP TABLE IF EXISTS category_counts;
CREATE TABLE category_counts (category TEXT, game_count INTEGER);

DROP TABLE IF EXISTS games_by_year;
CREATE TABLE games_by_year (release_year INTEGER, game_count INTEGER);

DROP TABLE IF EXISTS games_by_year_month;
CREATE TABLE games_by_year_month (release_year INTEGER, release_month TEXT, game_count INTEGER);

DROP TABLE IF EXISTS median_price_by_year;
CREATE TABLE median_price_by_year (release_year INTEGER, median_price REAL);

DROP TABLE IF EXISTS free_to_play_trend;
CREATE TABLE free_to_play_trend (release_year INTEGER, free_games INTEGER, total_games INTEGER, free_percentage REAL);

DROP TABLE IF EXISTS genre_combinations;
CREATE TABLE genre_combinations (genre_combo TEXT, game_count INTEGER);

DROP TABLE IF EXISTS free_genres;
CREATE TABLE free_genres (genre TEXT, free_count INTEGER, total_count INTEGER, free_percentage REAL);

DROP TABLE IF EXISTS controller_support;
CREATE TABLE controller_support (release_year INTEGER, controller_games INTEGER, total_games INTEGER, controller_percentage REAL);

DROP TABLE IF EXISTS indie_vs_non_indie;
CREATE TABLE indie_vs_non_indie (category TEXT, avg_price REAL, game_count INTEGER);
EOF
echo "✓ Database tables created"

# -----------------------------
# 6. Compute all aggregations (OPTIMIZED)
# -----------------------------
echo ""
echo "=== Step 6: Computing all aggregations ==="

# Single AWK pass for multiple computations
echo "Computing counts, distributions, and trends in combined passes..."

# Pass 1: Basic counts, price brackets, temporal data, trends (single file read)
awk -F',' '
NR==1 {next}
{
    total_games++

    # Developer and publisher tracking
    devs[$9]++
    pubs[$10]++

    # Free vs Paid
    if($7==0) {
        free_games++
    } else {
        paid_games++
    }

    # Self vs External publishing
    if($9==$10) self_pub++
    else ext_pub++

    # Price brackets
    p=$7
    if(p==0) price_bracket["Free"]++
    else if(p<=2) price_bracket["0.49–2.00"]++
    else if(p<=5) price_bracket["2.01–5.00"]++
    else if(p<=10) price_bracket["5.01–10.00"]++
    else if(p<=20) price_bracket["10.01–20.00"]++
    else if(p<=40) price_bracket["20.01–40.00"]++
    else if(p<=60) price_bracket["40.01–60.00"]++
    else if(p<=100) price_bracket["60.01–100.00"]++
    else price_bracket["100+"]++

    # Games by year
    year=$3
    games_by_year[year]++

    # Year-month
    split($4,date_parts," ")
    month=date_parts[1]
    year_month[year","month]++

    # Price by year for median calculation
    prices_by_year[year]=prices_by_year[year]" "$7

    # Free-to-play trend
    total_by_year[year]++
    if($7==0) free_by_year[year]++

    # Controller support
    if($6 ~ /[Cc]ontroller/ || $6 ~ /[Gg]amepad/) controller_by_year[year]++

    # Indie vs Non-Indie
    if($5 ~ /Indie/) {
        indie_sum+=$7
        indie_count++
    } else {
        non_indie_sum+=$7
        non_indie_count++
    }

    # Genre combinations
    gsub(/;/,", ",$5)
    genre_combos[$5]++

    # Parse genres for individual counts and free genres
    split($5,genres,", ")
    for(i in genres) {
        g=genres[i]
        gsub(/^[ \t]+|[ \t]+$/,"",g)
        if(g!="") {
            genre_list[g]++
            if($7==0) free_genre_list[g]++
        }
    }

    # Parse categories
    split($6,cats,";")
    for(i in cats) {
        c=cats[i]
        gsub(/^[ \t]+|[ \t]+$/,"",c)
        if(c!="") category_list[c]++
    }
}
END {
    # Write counts
    print "INSERT INTO counts VALUES (\"total_games\", "total_games");"
    print "INSERT INTO counts VALUES (\"num_genres\", "length(genre_list)");"
    print "INSERT INTO counts VALUES (\"num_categories\", "length(category_list)");"
    print "INSERT INTO counts VALUES (\"num_developers\", "length(devs)");"
    print "INSERT INTO counts VALUES (\"num_publishers\", "length(pubs)");"
    print "INSERT INTO counts VALUES (\"num_free_games\", "free_games");"
    print "INSERT INTO counts VALUES (\"num_paid_games\", "paid_games");"
    print "INSERT INTO counts VALUES (\"self_published\", "self_pub");"
    print "INSERT INTO counts VALUES (\"external_published\", "ext_pub");"

    # Write price brackets
    for(r in price_bracket)
        print "INSERT INTO price_brackets VALUES (\""r"\","price_bracket[r]");"

    # Write games by year
    for(y in games_by_year)
        print "INSERT INTO games_by_year VALUES ("y","games_by_year[y]");"

    # Write year-month
    for(ym in year_month) {
        split(ym,parts,",")
        print "INSERT INTO games_by_year_month VALUES ("parts[1]",\""parts[2]"\","year_month[ym]");"
    }

    # Write free-to-play trend
    for(y in total_by_year) {
        free_count=(free_by_year[y] ? free_by_year[y] : 0)
        pct=(free_count/total_by_year[y])*100
        print "INSERT INTO free_to_play_trend VALUES ("y","free_count","total_by_year[y]","pct");"
    }

    # Write controller support
    for(y in total_by_year) {
        ctrl_count=(controller_by_year[y] ? controller_by_year[y] : 0)
        pct=(ctrl_count/total_by_year[y])*100
        print "INSERT INTO controller_support VALUES ("y","ctrl_count","total_by_year[y]","pct");"
    }

    # Write indie vs non-indie
    if(indie_count > 0) {
        indie_avg=indie_sum/indie_count
        print "INSERT INTO indie_vs_non_indie VALUES (\"Indie\","indie_avg","indie_count");"
    }
    if(non_indie_count > 0) {
        non_indie_avg=non_indie_sum/non_indie_count
        print "INSERT INTO indie_vs_non_indie VALUES (\"Non-Indie\","non_indie_avg","non_indie_count");"
    }

    # Write genre counts
    for(g in genre_list)
        print "INSERT INTO genre_counts VALUES (\""g"\","genre_list[g]");"

    # Write category counts
    for(c in category_list)
        print "INSERT INTO category_counts VALUES (\""c"\","category_list[c]");"

    # Write free genres
    for(g in genre_list) {
        free_count=(free_genre_list[g] ? free_genre_list[g] : 0)
        pct=(free_count/genre_list[g])*100
        print "INSERT INTO free_genres VALUES (\""g"\","free_count","genre_list[g]","pct");"
    }
}' steam_script.csv | sqlite3 analysis.db

# Pass 2: Median price by year (requires sorting, separate pass)
echo "Computing median prices..."
awk -F',' 'NR>1 {prices[$3]=prices[$3]" "$7} END {for(y in prices) print y, prices[y]}' steam_script.csv | \
while read year prices; do
  median=$(echo "$prices" | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END {print a[int(NR/2+0.5)]}')
  echo "INSERT INTO median_price_by_year VALUES ($year, $median);"
done | sqlite3 analysis.db

# Pass 3: Top 20 genre combinations (requires sorting, separate pass)
echo "Computing top genre combinations..."
awk -F',' 'NR>1 {
  gsub(/;/,", ",$5)
  combos[$5]++
}
END {
  for(c in combos) print combos[c]"\t"c
}' steam_script.csv | sort -rn | head -20 | \
awk -F'\t' '{gsub(/"/,"\"\"",$2); print "INSERT INTO genre_combinations VALUES (\""$2"\"," $1 ");"}' | \
sqlite3 analysis.db

echo ""
echo "✓ All aggregations completed!"
echo "Database file: analysis.db"
echo "Tables populated: 12"
echo ""

# -----------------------------
# 7. Create and launch Streamlit dashboard
# -----------------------------
echo "=== Step 7: Creating Streamlit dashboard ==="
cat > app.py <<'EOFAPP'
import sqlite3
import pandas as pd
import streamlit as st
import plotly.express as px
import plotly.graph_objects as go

st.set_page_config(layout="wide", page_title="Steam Games Analytics")

st.markdown("""
<style>
    .block-container {padding-top: 1rem; padding-bottom: 0rem;}
    h1 {font-size: 2rem; margin-bottom: 0.5rem;}
    h2 {font-size: 1.2rem; margin-top: 0.5rem; margin-bottom: 0.3rem;}

    [data-testid="metric-container"] {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%) !important;
        padding: 1rem !important;
        border-radius: 0.5rem !important;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1) !important;
    }

    [data-testid="stMetricLabel"] {
        color: rgba(255,255,255,0.95) !important;
        font-weight: 500 !important;
        font-size: 0.9rem !important;
    }

    [data-testid="stMetricValue"] {
        font-size: 1.8rem !important;
        color: white !important;
        font-weight: 700 !important;
    }

    [data-testid="metric-container"] * {
        color: white !important;
    }
</style>
""", unsafe_allow_html=True)

@st.cache_data
def load(q):
    with sqlite3.connect("analysis.db") as c:
        return pd.read_sql(q, c)

st.title("🎮 Steam Games Analytics Dashboard")

counts = load("SELECT * FROM counts")
counts_dict = dict(zip(counts['metric'], counts['value']))

cols = st.columns(9)
metrics = [
    ("Total Games", "total_games", "🎯"),
    ("Genres", "num_genres", "🎨"),
    ("Categories", "num_categories", "📂"),
    ("Publishers", "num_publishers", "🏢"),
    ("Developers", "num_developers", "👨‍💻"),
    ("Free Games", "num_free_games", "🆓"),
    ("Paid Games", "num_paid_games", "💰"),
    ("Self-Pub", "self_published", "📦"),
    ("Ext-Pub", "external_published", "🤝")
]
for col, (label, key, icon) in zip(cols, metrics):
    col.metric(f"{icon} {label}", f"{counts_dict.get(key, 0):,}")

st.markdown("---")

col1, col2, col3, col4 = st.columns([1.2, 1, 1, 1])

with col1:
    st.subheader("📊 Games Released Over Time")
    by_year = load("SELECT * FROM games_by_year ORDER BY release_year")
    by_year['cumulative_games'] = by_year['game_count'].cumsum()
    fig = px.area(by_year, x='release_year', y='cumulative_games', color_discrete_sequence=['#1f77b4'])
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="Year", yaxis_title="Cumulative Games", showlegend=False)
    st.plotly_chart(fig, width='stretch')

with col2:
    st.subheader("💵 Price Distribution")
    price_dist = load("SELECT * FROM price_brackets")
    price_order = ["Free", "0.49–2.00", "2.01–5.00", "5.01–10.00", "10.01–20.00", "20.01–40.00", "40.01–60.00", "60.01–100.00", "100+"]
    price_dist['price_range'] = pd.Categorical(price_dist['price_range'], categories=price_order, ordered=True)
    price_dist = price_dist.sort_values('price_range')
    fig = px.bar(price_dist, x='price_range', y='game_count', color='game_count', color_continuous_scale='Blues')
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), showlegend=False, xaxis_tickangle=-45, xaxis_title="Price Range", yaxis_title="Number of Games")
    fig.update_coloraxes(showscale=False)
    st.plotly_chart(fig, width='stretch')

with col3:
    st.subheader("🆓 Free vs Paid")
    free_paid = pd.DataFrame({'Type': ['Free', 'Paid'], 'Count': [counts_dict.get('num_free_games', 0), counts_dict.get('num_paid_games', 0)]})
    fig = px.pie(free_paid, values='Count', names='Type', color='Type', color_discrete_map={'Free': '#90EE90', 'Paid': '#87CEEB'})
    fig.update_traces(textposition='inside', textinfo='percent+label')
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=10), showlegend=False)
    st.plotly_chart(fig, width='stretch')

with col4:
    st.subheader("💰 Indie vs Non-Indie")
    indie_data = load("SELECT * FROM indie_vs_non_indie")
    fig = px.bar(indie_data, x='category', y='avg_price', color='category', color_discrete_map={'Indie': '#9b59b6', 'Non-Indie': '#3498db'}, text='avg_price')
    fig.update_traces(texttemplate='$%{text:.2f}', textposition='outside')
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), showlegend=False, xaxis_title="", yaxis_title="Avg Price ($)")
    st.plotly_chart(fig, width='stretch')

st.markdown("---")

col1, col2, col3 = st.columns(3)

with col1:
    st.subheader("📈 Median Price Trend")
    median_price = load("SELECT * FROM median_price_by_year ORDER BY release_year")
    fig = px.line(median_price, x='release_year', y='median_price', markers=True, color_discrete_sequence=['#e67e22'])
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="Year", yaxis_title="Median Price ($)", showlegend=False)
    st.plotly_chart(fig, width='stretch')

with col2:
    st.subheader("🆓 Free-to-Play Growth")
    f2p_trend = load("SELECT * FROM free_to_play_trend ORDER BY release_year")
    fig = px.line(f2p_trend, x='release_year', y='free_percentage', markers=True, color_discrete_sequence=['#27ae60'])
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="Year", yaxis_title="Free Games (%)", showlegend=False)
    st.plotly_chart(fig, width='stretch')

with col3:
    st.subheader("🎮 Controller Support")
    controller = load("SELECT * FROM controller_support ORDER BY release_year")
    fig = px.line(controller, x='release_year', y='controller_percentage', markers=True, color_discrete_sequence=['#8e44ad'])
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="Year", yaxis_title="Controller Support (%)", showlegend=False)
    st.plotly_chart(fig, width='stretch')

st.markdown("---")

col1, col2, col3 = st.columns([1, 1, 1.2])

with col1:
    st.subheader("🎨 Top 10 Genres")
    genres = load("SELECT * FROM genre_counts ORDER BY game_count DESC LIMIT 10")
    fig = px.bar(genres, x='game_count', y='genre', orientation='h', color='game_count', color_continuous_scale='Viridis')
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="Games", yaxis_title="", showlegend=False, yaxis={'categoryorder':'total ascending'})
    fig.update_coloraxes(showscale=False)
    st.plotly_chart(fig, width='stretch')

with col2:
    st.subheader("📂 Top 10 Categories")
    categories = load("SELECT * FROM category_counts ORDER BY game_count DESC LIMIT 10")
    fig = px.bar(categories, x='game_count', y='category', orientation='h', color='game_count', color_continuous_scale='Plasma')
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="Games", yaxis_title="", showlegend=False, yaxis={'categoryorder':'total ascending'})
    fig.update_coloraxes(showscale=False)
    st.plotly_chart(fig, width='stretch')

with col3:
    st.subheader("🆓 Top Free-to-Play Genres")
    free_genres = load("SELECT * FROM free_genres ORDER BY free_percentage DESC LIMIT 10")
    fig = px.bar(free_genres, x='genre', y='free_percentage', color='free_percentage', color_continuous_scale='RdYlGn')
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="", yaxis_title="Free-to-Play %", showlegend=False, xaxis_tickangle=-45)
    fig.update_coloraxes(showscale=False)
    st.plotly_chart(fig, width='stretch')

st.markdown("---")

st.subheader("🔀 Top 15 Genre Combinations")
genre_combos = load("SELECT * FROM genre_combinations ORDER BY game_count DESC LIMIT 15")
fig = px.bar(genre_combos, x='game_count', y='genre_combo', orientation='h', color='game_count', color_continuous_scale='Blues')
fig.update_layout(height=400, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="Games", yaxis_title="", showlegend=False, yaxis={'categoryorder':'total ascending'})
fig.update_coloraxes(showscale=False)
st.plotly_chart(fig, width='stretch')

st.markdown("---")

# Database Tables Section
st.title("📊 Database Tables")
st.markdown("Below are all the aggregated tables stored in the SQLite database.")

# Get list of all tables
with sqlite3.connect("analysis.db") as conn:
    tables = pd.read_sql("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name", conn)
    table_list = tables['name'].tolist()

# Create tabs for each table
tabs = st.tabs(table_list)

for tab, table_name in zip(tabs, table_list):
    with tab:
        st.subheader(f"Table: {table_name}")
        df = load(f"SELECT * FROM {table_name}")

        # Display row count
        st.caption(f"Total rows: {len(df)}")

        # Display the dataframe
        st.dataframe(df, width='stretch', height=400)

        # Add download button for each table
        csv = df.to_csv(index=False).encode('utf-8')
        st.download_button(
            label=f"📥 Download {table_name} as CSV",
            data=csv,
            file_name=f"{table_name}.csv",
            mime="text/csv",
        )

st.markdown("---")

# Complete Dataset Section
st.title("📋 Complete Dataset")
st.markdown("The full cleaned dataset used for all analyses above.")

# Load the complete CSV
complete_df = pd.read_csv("steam_script.csv")

st.caption(f"Total rows: {len(complete_df):,}")
st.caption(f"Total columns: {len(complete_df.columns)}")

# Display column info
with st.expander("📌 View Column Information"):
    col_info = pd.DataFrame({
        'Column Name': complete_df.columns,
        'Data Type': complete_df.dtypes.astype(str),
        'Non-Null Count': complete_df.count().values,
        'Sample Value': [str(complete_df[col].iloc[0]) if len(complete_df) > 0 else None for col in complete_df.columns]
    })
    st.dataframe(col_info, width='stretch')

# Display the complete dataset
st.dataframe(complete_df, width='stretch', height=500)

# Download button for complete dataset
csv_full = complete_df.to_csv(index=False).encode('utf-8')
st.download_button(
    label="📥 Download Complete Dataset as CSV",
    data=csv_full,
    file_name="steam_complete_dataset.csv",
    mime="text/csv",
)

st.markdown("---")
st.markdown("<div style='text-align: center; color: #888; font-size: 0.85rem;'>Steam Games Analytics Dashboard | Shell + SQLite + Streamlit + Plotly</div>", unsafe_allow_html=True)
EOFAPP

echo "✓ Dashboard created: app.py"
echo ""
streamlit run app.py
