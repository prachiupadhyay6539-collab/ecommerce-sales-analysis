/*
============================================================
PROJECT     : E-Commerce Sales Performance Analysis
DATASET     : Sample Superstore
TOOL        : SQL Server (T-SQL)
METHODOLOGY : CRISP-DM
PHASE       : Phase 3 — Data Preparation
AUTHOR      : Prachi Upadhyay
DATE        : April 2025
============================================================
*/


-- ============================================================
-- SECTION 1: INITIAL EXPLORATION
-- ============================================================

-- View full dataset
SELECT *
FROM samplesuperstore;

-- ============================================================
-- SECTION 2: DUPLICATE DETECTION & REMOVAL
-- ============================================================

-- Step 1: Identify duplicates based on order + product combination
SELECT 
	order_id,
	product_id,
	COUNT(*) AS duplicate_count
FROM samplesuperstore
Group by order_id, product_id
Having Count (*) >1;

-- Step 2: Remove exact duplicates using ROW_NUMBER()
-- Keeps the first occurrence (lowest row_id), deletes the rest
With cte AS(
	SELECT *,
			ROW_NUMBER() OVER(PARTITION BY order_id, product_id, sales, quantity, discount, profit
			Order by row_id
			) AS rn
		FROM samplesuperstore
	)
	DELETE FROM cte Where rn>1;

-- ============================================================
-- SECTION 3: TEXT COLUMN STANDARDIZATION
-- ============================================================

-- Apply proper casing and trim whitespace
UPDATE samplesuperstore
SET 
    customer_name = UPPER(LEFT(LTRIM(RTRIM(customer_name)),1)) 
                    + LOWER(SUBSTRING(LTRIM(RTRIM(customer_name)),2,LEN(customer_name))),
    product_name  = UPPER(LEFT(LTRIM(RTRIM(product_name)),1)) 
                    + LOWER(SUBSTRING(LTRIM(RTRIM(product_name)),2,LEN(product_name))),
    city          = UPPER(LEFT(LTRIM(RTRIM(city)),1)) 
                    + LOWER(SUBSTRING(LTRIM(RTRIM(city)),2,LEN(city))),
    state_province = UPPER(LEFT(LTRIM(RTRIM(state_province)),1)) 
                     + LOWER(SUBSTRING(LTRIM(RTRIM(state_province)),2,LEN(state_province)));

-- Verify result
Select top 10
	customer_name,
	city,
	state_province
FROM samplesuperstore;

-- ============================================================
-- SECTION 4: DATE VALIDATION
-- ============================================================

-- Preview date columns
SELECT TOP 50 order_date, ship_date
FROM samplesuperstore;

-- Check for logically invalid dates (shipped before ordered)
SELECT *
FROM samplesuperstore
WHERE ship_date < order_date;

--Checking for missing dates
SELECT *
FROM samplesuperstore
WHERE order_date IS NULL
   OR ship_date IS NULL;

-- Check overall date range of dataset
SELECT 
    MIN(order_date) AS MinDate, 
    MAX(order_date) AS MaxDate
FROM samplesuperstore;

-- ============================================================
-- SECTION 5: NUMERIC VALIDATION
-- ============================================================

-- Check for invalid sales, quantity and discount values
SELECT *
FROM samplesuperstore
WHERE 
    sales IS NULL
    OR quantity <= 0
    OR discount < 0
    OR discount > 1;

-- Check value ranges across key numeric columns
SELECT 
    MAX(sales) AS max_sales,
    MIN(sales) AS min_sales,
    MAX(profit) AS max_profit,
    MIN(profit) AS min_profit,
    MAX(quantity) AS max_quantity,
    MIN(quantity) AS min_quantity
FROM samplesuperstore;

-- Investigate heavily loss-making orders
SELECT TOP 10 *
FROM samplesuperstore
Where profit < -1000
Order by profit ASC;

-- ============================================================
-- SECTION 6: FEATURE ENGINEERING — PROFIT MARGIN
-- ============================================================

-- Add profit_margin column (profit as a % of sales)
ALTER TABLE samplesuperstore
ADD profit_margin DECIMAL(10,4);

-- Populate profit_margin; NULLIF prevents division-by-zero errors
UPDATE samplesuperstore
SET profit_margin = profit / NULLIF(sales, 0);

-- ============================================================
-- SECTION 7: DATASET SUMMARY STATISTICS
-- ============================================================

-- Total rows vs unique orders
SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders
FROM samplesuperstore;

-- Total revenue
SELECT SUM(sales) AS total_revenue FROM samplesuperstore;

-- ============================================================
-- SECTION 8: PRESERVE CLEAN DATA
-- ============================================================

-- Create a clean copy of the dataset before further analysis
SELECT * 
INTO samplesuperstore_clean FROM samplesuperstore;


/*
============================================================
PROJECT     : E-Commerce Sales Performance Analysis
DATASET     : Sample Superstore
TOOL        : SQL Server (T-SQL)
METHODOLOGY : CRISP-DM
PHASE       : Phase 4 — Data Analysis
AUTHOR      : Prachi Upadhyay
DATE        : April 2025

BUSINESS PROBLEM:
The company generates significant sales but lacks clarity
on profitability drivers. This phase answers 5 analytical
questions tied directly to the business problem.
============================================================
*/


-- ============================================================
-- Q1: CATEGORY & SUB-CATEGORY PROFITABILITY
-- Is discounting causing losses in specific categories?
-- ============================================================

-- Overview: profit and margin by category
SELECT
    category,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct,
    ROUND(AVG(discount) * 100, 2)               AS avg_discount_pct
FROM samplesuperstore_clean
GROUP BY category
ORDER BY total_profit ASC;


-- Drill down: sub-category level to find exact loss-makers
SELECT
    category,
    sub_category,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct,
    ROUND(AVG(discount) * 100, 2)               AS avg_discount_pct,
    COUNT(DISTINCT order_id)                    AS total_orders
FROM samplesuperstore_clean
GROUP BY category, sub_category
ORDER BY total_profit ASC;


-- Discount impact: classify orders by discount band and measure profit
-- This directly tests whether high discounts cause losses
SELECT
    CASE
        WHEN discount = 0           THEN '0% - No Discount'
        WHEN discount <= 0.10       THEN '1-10%'
        WHEN discount <= 0.20       THEN '11-20%'
        WHEN discount <= 0.30       THEN '21-30%'
        WHEN discount <= 0.40       THEN '31-40%'
        ELSE                             '40%+ High Risk'
    END                                         AS discount_band,
    COUNT(*)                                    AS total_orders,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct
FROM samplesuperstore_clean
GROUP BY
    CASE
        WHEN discount = 0           THEN '0% - No Discount'
        WHEN discount <= 0.10       THEN '1-10%'
        WHEN discount <= 0.20       THEN '11-20%'
        WHEN discount <= 0.30       THEN '21-30%'
        WHEN discount <= 0.40       THEN '31-40%'
        ELSE                             '40%+ High Risk'
    END
ORDER BY avg_profit_margin_pct ASC;

-- ============================================================
-- Q2: SALES & PROFIT TREND OVER TIME
-- Is revenue growth translating into profit growth?
-- ============================================================

-- Monthly trend with both sales AND profit to detect the gap
SELECT
    YEAR(order_date)                            AS order_year,
    MONTH(order_date)                           AS month_number,
    DATENAME(MONTH, order_date)                 AS month_name,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct
FROM samplesuperstore_clean
GROUP BY
    YEAR(order_date),
    MONTH(order_date),
    DATENAME(MONTH, order_date)
ORDER BY order_year, month_number;


-- Yearly summary: are we growing profitably year over year?
SELECT
    YEAR(order_date)                            AS order_year,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct,
    COUNT(DISTINCT order_id)                    AS total_orders
FROM samplesuperstore_clean
GROUP BY YEAR(order_date)
ORDER BY order_year;


-- ============================================================
-- Q3: REGIONAL PERFORMANCE
-- Which regions have strong sales but weak profit margins?
-- ============================================================

-- Region level: find where sales and profit don't align
SELECT
    region,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct,
    ROUND(AVG(discount) * 100, 2)               AS avg_discount_pct,
    COUNT(DISTINCT order_id)                    AS total_orders
FROM samplesuperstore_clean
GROUP BY region
ORDER BY avg_profit_margin_pct ASC;


-- State level drill down: find specific states bleeding profit
SELECT
    region,
    state_province,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct,
    ROUND(AVG(discount) * 100, 2)               AS avg_discount_pct
FROM samplesuperstore_clean
GROUP BY region, state_province
ORDER BY total_profit ASC;


-- ============================================================
-- Q4: PRODUCT PERFORMANCE
-- Which products drive profit and which destroy it?
-- ============================================================

-- Top 10 most profitable products
SELECT TOP 10
    product_name,
    category,
    sub_category,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct
FROM samplesuperstore_clean
GROUP BY product_name, category, sub_category
ORDER BY total_profit DESC;


-- Bottom 10 loss-making products
SELECT TOP 10
    product_name,
    category,
    sub_category,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct,
    ROUND(AVG(discount) * 100, 2)               AS avg_discount_pct
FROM samplesuperstore_clean
GROUP BY product_name, category, sub_category
ORDER BY total_profit ASC;


-- ============================================================
-- Q5: CUSTOMER SEGMENT ANALYSIS
-- Which segments are most profitable and which are over-discounted?
-- ============================================================

-- Segment level profitability and discount behaviour
SELECT
    segment,
    COUNT(DISTINCT customer_id)                 AS total_customers,
    COUNT(DISTINCT order_id)                    AS total_orders,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct,
    ROUND(AVG(discount) * 100, 2)               AS avg_discount_pct
FROM samplesuperstore_clean
GROUP BY segment
ORDER BY avg_profit_margin_pct ASC;


-- Segment + category cross analysis
-- Reveals which segment is being over-discounted in which category
SELECT
    segment,
    category,
    ROUND(SUM(sales), 2)                        AS total_sales,
    ROUND(SUM(profit), 2)                       AS total_profit,
    ROUND(AVG(profit_margin) * 100, 2)          AS avg_profit_margin_pct,
    ROUND(AVG(discount) * 100, 2)               AS avg_discount_pct
FROM samplesuperstore_clean
GROUP BY segment, category
ORDER BY avg_profit_margin_pct ASC;