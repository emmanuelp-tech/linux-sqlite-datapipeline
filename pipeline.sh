#!/bin/bash

set -e

# -----------------------------
# 1. Install requirements
# -----------------------------
sudo apt update
sudo apt install -y perl sqlite3 pipx python3

pipx install streamlit || true
pipx inject streamlit pandas plotly

# -----------------------------
# 2. Clean CSV
# -----------------------------

perl -pe 's/"([^"]*)"/my $s=$1; $s=~s@,@;@g; $s/ge' steam.csv > steam_clean.csv
sed -i 's/\r$//' steam_clean.csv

# -----------------------------
# 3. Find missing values (report)
# -----------------------------
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
}' steam_clean.csv

# -----------------------------
# 4. Remove rows with missing values
# -----------------------------
awk -F',' '
NR==1 {print; next}
{
  for(i=1;i<=NF;i++)
    if($i=="" || $i~/^[[:space:]]*$/ || $i=="NA" || $i=="NaN" ||
       $i=="null" || $i=="NULL" || $i=="None" ||
       $i=="[]" || $i=="{}" || $i=="()" || $i=="N/A" || $i=="n/a")
      next
  print
}' steam_clean.csv > steam_script.csv

# -----------------------------
# 5. Create SQLite tables
# -----------------------------
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

# -----------------------------
# 6. Populate counts
# -----------------------------
wc -l steam_script.csv | awk '{print $1-1}' \
| awk '{print "INSERT INTO counts VALUES (\"total_games\", "$1");"}' | sqlite3 analysis.db

cut -d',' -f5 steam_script.csv | tr ';' '\n' | sed '1d' | sed 's/^ *//;s/ *$//' | grep -v '^$' | sort -u | wc -l \
| awk '{print "INSERT INTO counts VALUES (\"num_genres\", "$1");"}' | sqlite3 analysis.db

cut -d',' -f6 steam_script.csv | tr ';' '\n' | sed '1d' | sed 's/^ *//;s/ *$//' | grep -v '^$' | sort -u | wc -l \
| awk '{print "INSERT INTO counts VALUES (\"num_categories\", "$1");"}' | sqlite3 analysis.db

cut -d',' -f9 steam_script.csv | sed '1d' | sort -u | wc -l \
| awk '{print "INSERT INTO counts VALUES (\"num_developers\", "$1");"}' | sqlite3 analysis.db

cut -d',' -f10 steam_script.csv | sed '1d' | sort -u | wc -l \
| awk '{print "INSERT INTO counts VALUES (\"num_publishers\", "$1");"}' | sqlite3 analysis.db

awk -F',' 'NR>1 && $7==0 {c++} END{print c}' steam_script.csv \
| awk '{print "INSERT INTO counts VALUES (\"num_free_games\", "$1");"}' | sqlite3 analysis.db

awk -F',' 'NR>1 && $7>0 {c++} END{print c}' steam_script.csv \
| awk '{print "INSERT INTO counts VALUES (\"num_paid_games\", "$1");"}' | sqlite3 analysis.db

# Self-published count
awk -F',' 'NR>1 {if($9==$10) self++; total++} END{print self}' steam_script.csv \
| awk '{print "INSERT INTO counts VALUES (\"self_published\", "$1");"}' | sqlite3 analysis.db

awk -F',' 'NR>1 {if($9!=$10) ext++} END{print ext}' steam_script.csv \
| awk '{print "INSERT INTO counts VALUES (\"external_published\", "$1");"}' | sqlite3 analysis.db

# -----------------------------
# 7. Price brackets
# -----------------------------
awk -F',' 'NR>1{
 p=$7
 if(p==0) r="Free"
 else if(p<=2) r="0.49–2.00"
 else if(p<=5) r="2.01–5.00"
 else if(p<=10) r="5.01–10.00"
 else if(p<=20) r="10.01–20.00"
 else if(p<=40) r="20.01–40.00"
 else if(p<=60) r="40.01–60.00"
 else if(p<=100) r="60.01–100.00"
 else r="100+"
 count[r]++
}
END{for(r in count) print "INSERT INTO price_brackets VALUES (\""r"\","count[r]");"}' \
steam_script.csv | sqlite3 analysis.db

# -----------------------------
# 8. Genres & Categories
# -----------------------------
cut -d',' -f5 steam_script.csv | tr ';' '\n' | sed '1d' | sed 's/^ *//;s/ *$//' | grep -v '^$' \
| sort | uniq -c | awk '{print "INSERT INTO genre_counts VALUES (\"" $2 "\"," $1 ");"}' \
| sqlite3 analysis.db

cut -d',' -f6 steam_script.csv | tr ';' '\n' | sed '1d' | sed 's/^ *//;s/ *$//' | grep -v '^$' \
| sort | uniq -c | awk '{print "INSERT INTO category_counts VALUES (\"" $2 "\"," $1 ");"}' \
| sqlite3 analysis.db

# -----------------------------
# 9. Year & Year-Month
# -----------------------------
awk -F',' 'NR>1{c[$3]++} END{for(y in c) print "INSERT INTO games_by_year VALUES ("y","c[y]");"}' \
steam_script.csv | sqlite3 analysis.db

awk -F',' 'NR>1{
 split($4,a," ")
 ym[$3","a[1]]++
}
END{
 for(k in ym){split(k,b,","); print "INSERT INTO games_by_year_month VALUES ("b[1]",\""b[2]"\","ym[k]");"}
}' steam_script.csv | sqlite3 analysis.db

# -----------------------------
# 10. Median Price by Year
# -----------------------------
awk -F',' 'NR>1 {prices[$3]=prices[$3]" "$7} END {for(y in prices) print y, prices[y]}' steam_script.csv | \
while read year prices; do
  median=$(echo "$prices" | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END {print a[int(NR/2+0.5)]}')
  echo "INSERT INTO median_price_by_year VALUES ($year, $median);"
done | sqlite3 analysis.db

# -----------------------------
# 11. Free-to-Play Trend
# -----------------------------
awk -F',' 'NR>1 {
  year=$3
  if($7==0) free[year]++
  total[year]++
}
END {
  for(y in total) {
    pct=(free[y]/total[y])*100
    print "INSERT INTO free_to_play_trend VALUES ("y","free[y]","total[y]","pct");"
  }
}' steam_script.csv | sqlite3 analysis.db

# -----------------------------
# 12. Genre Combinations (Top 20)
# -----------------------------
awk -F',' 'NR>1 {
  gsub(/;/,", ",$5)
  combos[$5]++
}
END {
  for(c in combos) print combos[c]"\t"c
}' steam_script.csv | sort -nr | head -20 | \
awk -F'\t' '{gsub(/"/,"\"\"",$2); print "INSERT INTO genre_combinations VALUES (\""$2"\"," $1 ");"}' | \
sqlite3 analysis.db

# -----------------------------
# 13. Free-to-Play Genres
# -----------------------------
awk -F',' 'NR>1 {
  split($5,genres,";")
  for(i in genres) {
    gsub(/^[ \t]+|[ \t]+$/,"",genres[i])
    if(genres[i]!="") {
      total_g[genres[i]]++
      if($7==0) free_g[genres[i]]++
    }
  }
}
END {
  for(g in total_g) {
    free_count = (free_g[g] ? free_g[g] : 0)
    pct=(free_count/total_g[g])*100
    gsub(/"/,"\"\"",g)
    print "INSERT INTO free_genres VALUES (\""g"\","free_count","total_g[g]","pct");"
  }
}' steam_script.csv | sqlite3 analysis.db

# -----------------------------
# 14. Controller Support Over Time
# -----------------------------
awk -F',' 'NR>1 {
  year=$3
  total[year]++
  if($6 ~ /[Cc]ontroller/ || $6 ~ /[Gg]amepad/) controller[year]++
}
END {
  for(y in total) {
    pct=(controller[y]/total[y])*100
    print "INSERT INTO controller_support VALUES ("y","controller[y]","total[y]","pct");"
  }
}' steam_script.csv | sqlite3 analysis.db

# -----------------------------
# 15. Indie vs Non-Indie Average Price
# -----------------------------
awk -F',' 'NR>1 {
  if($5 ~ /Indie/) {indie_sum+=$7; indie_count++}
  else {non_indie_sum+=$7; non_indie_count++}
}
END {
  indie_avg=indie_sum/indie_count
  non_indie_avg=non_indie_sum/non_indie_count
  print "INSERT INTO indie_vs_non_indie VALUES (\"Indie\","indie_avg","indie_count");"
  print "INSERT INTO indie_vs_non_indie VALUES (\"Non-Indie\","non_indie_avg","non_indie_count");"
}' steam_script.csv | sqlite3 analysis.db

echo "Database populated with all analytics!"

# -----------------------------
# 16. Enhanced Streamlit Dashboard
# -----------------------------
cat > app.py <<'EOFAPP'
import sqlite3
import pandas as pd
import streamlit as st
import plotly.express as px
import plotly.graph_objects as go

# Page config
st.set_page_config(layout="wide", page_title="Steam Games Analytics")

# Custom CSS
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

# Title
st.title("🎮 Steam Games Analytics Dashboard")

# Load data
counts = load("SELECT * FROM counts")
counts_dict = dict(zip(counts['metric'], counts['value']))

# Row 1: Metrics
cols = st.columns(9)
metrics = [
    ("Total Games", "total_games", "🎯"),
    ("Genres", "num_genres", "🎨"),
    ("Categories", "num_categories", "📂"),
    ("Publishers", "num_publishers", "🏢"),
    ("Developers", "num_developers", "👨‍💻"),
    ("Free Games", "num_free_games", "🆓"),
    ("Paid Games", "num_paid_games", "💰"),
    ("Self-Pub", "self_published", "📝"),
    ("Ext-Pub", "external_published", "🤝")
]
for col, (label, key, icon) in zip(cols, metrics):
    col.metric(f"{icon} {label}", f"{counts_dict.get(key, 0):,}")

st.markdown("---")

# Row 2: Main visuals
col1, col2, col3, col4 = st.columns([1.2, 1, 1, 1])

with col1:
    st.subheader("📊 Games Released Over Time")
    by_year = load("SELECT * FROM games_by_year ORDER BY release_year")
    fig = px.area(by_year, x='release_year', y='game_count', color_discrete_sequence=['#1f77b4'])
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="Year", yaxis_title="Games", showlegend=False)
    st.plotly_chart(fig, width='stretch')

with col2:
    st.subheader("💵 Price Distribution")
    price_dist = load("SELECT * FROM price_brackets")
    price_order = ["Free", "0.49–2.00", "2.01–5.00", "5.01–10.00", "10.01–20.00", "20.01–40.00", "40.01–60.00", "60.01–100.00", "100+"]
    price_dist['price_range'] = pd.Categorical(price_dist['price_range'], categories=price_order, ordered=True)
    price_dist = price_dist.sort_values('price_range')
    fig = px.bar(price_dist, x='price_range', y='game_count', color='game_count', color_continuous_scale='Blues')
    fig.update_layout(height=260, margin=dict(l=10,r=10,t=10,b=30), showlegend=False, xaxis_tickangle=-45)
    fig.update_coloraxes(showscale=False)
    st.plotly_chart(fig, width='stretch')

with col3:
    st.subheader("🆓 Free vs Paid")
    free_paid = pd.DataFrame({'Type': ['Free', 'Paid'], 'Count': [counts_dict.get('num_free_games', 0), counts_dict.get('num_paid_games', 0)]})
    fig = px.pie(free_paid, values='Count', names='Type', color='Type', color_discrete_map={'Free': '#2ecc71', 'Paid': '#e74c3c'})
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

# Row 3: Advanced analytics
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

# Row 4: Genres and categories
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

# Row 5: Genre combinations
st.subheader("🔀 Top 15 Genre Combinations")
genre_combos = load("SELECT * FROM genre_combinations ORDER BY game_count DESC LIMIT 15")
fig = px.bar(genre_combos, x='game_count', y='genre_combo', orientation='h', color='game_count', color_continuous_scale='Blues')
fig.update_layout(height=400, margin=dict(l=10,r=10,t=10,b=30), xaxis_title="Games", yaxis_title="", showlegend=False, yaxis={'categoryorder':'total ascending'})
fig.update_coloraxes(showscale=False)
st.plotly_chart(fig, width='stretch')

# Footer
st.markdown("---")
st.markdown("<div style='text-align: center; color: #888; font-size: 0.85rem;'>Steam Games Analytics Dashboard | Shell + SQLite + Streamlit + Plotly</div>", unsafe_allow_html=True)
EOFAPP

# -----------------------------
# 17. Run Streamlit
# -----------------------------
streamlit run app.py