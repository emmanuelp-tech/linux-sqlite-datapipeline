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
st.title("📊 Database Tables - Complete Data")
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
