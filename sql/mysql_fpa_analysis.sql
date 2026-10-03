-- Financial Performance FP&A - MySQL
-- Source: project documentation

-- ============================================================
-- 2. Create and Select the Database
-- Purpose: Create a dedicated database for the project.
-- ============================================================
CREATE DATABASE IF NOT EXISTS fpa_analytics;
USE fpa_analytics;

-- ============================================================
-- 3. Inspect the Main Actuals Table
-- Purpose: Understand the columns and preview the SAP-style accounting data.
-- ============================================================
DESCRIBE acdoca_actuals;

SELECT *
FROM acdoca_actuals
LIMIT 10;

-- ============================================================
-- 4. Count Transactions and Documents
-- Purpose: Validate the overall size of the accounting dataset.
-- ============================================================
SELECT
    COUNT(*) AS total_transactions,
    COUNT(DISTINCT CONCAT(BUKRS, '-', GJAHR, '-', BELNR)) AS total_documents
FROM acdoca_actuals;

-- ============================================================
-- 5. Check the Available Companies, Years and Currencies
-- Purpose: Understand the scope of the financial dataset.
-- ============================================================
SELECT DISTINCT BUKRS AS company_code
FROM acdoca_actuals
ORDER BY BUKRS;

SELECT DISTINCT GJAHR AS fiscal_year
FROM acdoca_actuals
ORDER BY GJAHR;

SELECT WAERS AS currency, COUNT(*) AS transaction_count
FROM acdoca_actuals
GROUP BY WAERS
ORDER BY transaction_count DESC;

-- ============================================================
-- 6. Missing-Value Checks
-- Purpose: Identify important fields with NULL values.
-- ============================================================
SELECT
    SUM(CASE WHEN BUKRS IS NULL THEN 1 ELSE 0 END) AS missing_company_code,
    SUM(CASE WHEN GJAHR IS NULL THEN 1 ELSE 0 END) AS missing_fiscal_year,
    SUM(CASE WHEN BUDAT IS NULL THEN 1 ELSE 0 END) AS missing_posting_date,
    SUM(CASE WHEN HKONT IS NULL THEN 1 ELSE 0 END) AS missing_gl_account,
    SUM(CASE WHEN KOSTL IS NULL THEN 1 ELSE 0 END) AS missing_cost_center,
    SUM(CASE WHEN PRCTR IS NULL THEN 1 ELSE 0 END) AS missing_profit_center,
    SUM(CASE WHEN DMBTR IS NULL THEN 1 ELSE 0 END) AS missing_local_amount
FROM acdoca_actuals;

-- ============================================================
-- 7. Exact Duplicate Check
-- Purpose: Check whether identical accounting rows were loaded more than once.
-- ============================================================
SELECT
    BUKRS, BELNR, GJAHR, MONAT, BUDAT, BUZEI,
    HKONT, KOSTL, PRCTR, DMBTR, WAERS,
    COUNT(*) AS duplicate_count
FROM acdoca_actuals
GROUP BY
    BUKRS, BELNR, GJAHR, MONAT, BUDAT, BUZEI,
    HKONT, KOSTL, PRCTR, DMBTR, WAERS
HAVING COUNT(*) > 1;

-- ============================================================
-- 8. Join Actuals to the G/L Account Dimension
-- Purpose: Attach readable financial categories such as REVENUE, COGS, PERSONNEL, OPEX, DEPRECIATION and BALANCE_SHEET.
-- ============================================================
SELECT
    a.BUKRS AS company_code,
    a.GJAHR AS fiscal_year,
    a.MONAT AS fiscal_month,
    a.HKONT AS gl_account,
    g.TXT50 AS gl_account_name,
    g.CATEGORY AS financial_category,
    a.SHKZG AS debit_credit,
    a.DMBTR AS local_currency_amount,
    a.WAERS AS currency
FROM acdoca_actuals a
LEFT JOIN dim_gl_account g
    ON a.HKONT = g.HKONT
LIMIT 100;

-- ============================================================
-- 9. Financial Category Summary
-- Purpose: See transaction counts and amounts by financial category.
-- ============================================================
SELECT
    g.CATEGORY AS financial_category,
    COUNT(*) AS transaction_count,
    SUM(a.DMBTR) AS raw_amount
FROM acdoca_actuals a
LEFT JOIN dim_gl_account g
    ON a.HKONT = g.HKONT
GROUP BY g.CATEGORY
ORDER BY raw_amount DESC;

-- ============================================================
-- 10. Create a Signed Accounting Amount
-- Purpose: Convert SAP debit/credit direction into a convenient analytical sign.
-- ============================================================
SELECT
    a.*,
    CASE
        WHEN a.SHKZG = 'S' THEN a.DMBTR
        WHEN a.SHKZG = 'H' THEN -a.DMBTR
        ELSE NULL
    END AS signed_amount
FROM acdoca_actuals a;

-- ============================================================
-- 11. Create a Reusable Financial Analysis View
-- Purpose: Avoid repeating the join and signed-amount logic in every query.
-- ============================================================
CREATE OR REPLACE VIEW vw_financial_actuals AS
SELECT
    a.BUKRS AS company_code,
    a.BELNR AS document_number,
    a.GJAHR AS fiscal_year,
    a.MONAT AS fiscal_month,
    a.BUDAT AS posting_date,
    a.WAERS AS currency,
    a.BUZEI AS line_item,
    a.SHKZG AS debit_credit,
    a.HKONT AS gl_account,
    a.KOSTL AS cost_center,
    a.PRCTR AS profit_center,
    a.DMBTR AS local_currency_amount,
    g.TXT50 AS gl_account_name,
    g.CATEGORY AS financial_category,
    CASE
        WHEN a.SHKZG = 'S' THEN a.DMBTR
        WHEN a.SHKZG = 'H' THEN -a.DMBTR
        ELSE NULL
    END AS signed_amount
FROM acdoca_actuals a
LEFT JOIN dim_gl_account g
    ON a.HKONT = g.HKONT;

-- ============================================================
-- 12. Monthly Revenue Analysis
-- Purpose: Calculate revenue by company, year, month and currency.
-- ============================================================
SELECT
    company_code,
    fiscal_year,
    fiscal_month,
    currency,
    -SUM(signed_amount) AS revenue
FROM vw_financial_actuals
WHERE financial_category = 'REVENUE'
GROUP BY company_code, fiscal_year, fiscal_month, currency
ORDER BY company_code, fiscal_year, fiscal_month;

-- ============================================================
-- 13. Annual Revenue Trend
-- Purpose: Compare revenue across fiscal years without mixing currencies.
-- ============================================================
SELECT
    company_code,
    fiscal_year,
    currency,
    -SUM(signed_amount) AS annual_revenue
FROM vw_financial_actuals
WHERE financial_category = 'REVENUE'
GROUP BY company_code, fiscal_year, currency
ORDER BY company_code, fiscal_year;

-- ============================================================
-- 14. Expense Analysis by Category
-- Purpose: Analyze COGS, personnel, OPEX and depreciation separately.
-- ============================================================
SELECT
    company_code,
    fiscal_year,
    fiscal_month,
    currency,
    financial_category,
    SUM(signed_amount) AS signed_expense
FROM vw_financial_actuals
WHERE financial_category IN ('COGS', 'PERSONNEL', 'OPEX', 'DEPRECIATION')
GROUP BY
    company_code, fiscal_year, fiscal_month,
    currency, financial_category
ORDER BY company_code, fiscal_year, fiscal_month, financial_category;

-- ============================================================
-- 15. Monthly P&L Calculation
-- Purpose: Calculate Revenue, COGS, Gross Profit, operating expenses and Operating Profit.
-- ============================================================
WITH monthly_components AS (
    SELECT
        company_code,
        fiscal_year,
        fiscal_month,
        currency,
        -SUM(CASE WHEN financial_category = 'REVENUE'
                  THEN signed_amount ELSE 0 END) AS revenue,
        SUM(CASE WHEN financial_category = 'COGS'
                 THEN signed_amount ELSE 0 END) AS cogs,
        SUM(CASE WHEN financial_category = 'PERSONNEL'
                 THEN signed_amount ELSE 0 END) AS personnel,
        SUM(CASE WHEN financial_category = 'OPEX'
                 THEN signed_amount ELSE 0 END) AS opex,
        SUM(CASE WHEN financial_category = 'DEPRECIATION'
                 THEN signed_amount ELSE 0 END) AS depreciation
    FROM vw_financial_actuals
    GROUP BY company_code, fiscal_year, fiscal_month, currency
)
SELECT
    *,
    revenue + cogs AS gross_profit,
    revenue + cogs + personnel + opex + depreciation AS operating_profit
FROM monthly_components
ORDER BY company_code, fiscal_year, fiscal_month;

-- ============================================================
-- 16. Gross Margin and Operating Margin
-- Purpose: Convert P&L profit into percentage KPIs.
-- ============================================================
WITH pnl AS (
    SELECT
        company_code,
        fiscal_year,
        fiscal_month,
        currency,
        -SUM(CASE WHEN financial_category = 'REVENUE'
                  THEN signed_amount ELSE 0 END) AS revenue,
        SUM(CASE WHEN financial_category = 'COGS'
                 THEN signed_amount ELSE 0 END) AS cogs,
        SUM(CASE WHEN financial_category = 'PERSONNEL'
                 THEN signed_amount ELSE 0 END) AS personnel,
        SUM(CASE WHEN financial_category = 'OPEX'
                 THEN signed_amount ELSE 0 END) AS opex,
        SUM(CASE WHEN financial_category = 'DEPRECIATION'
                 THEN signed_amount ELSE 0 END) AS depreciation
    FROM vw_financial_actuals
    GROUP BY company_code, fiscal_year, fiscal_month, currency
)
SELECT
    *,
    revenue + cogs AS gross_profit,
    revenue + cogs + personnel + opex + depreciation AS operating_profit,
    100.0 * (revenue + cogs) / NULLIF(revenue, 0) AS gross_margin_pct,
    100.0 * (revenue + cogs + personnel + opex + depreciation)
        / NULLIF(revenue, 0) AS operating_margin_pct
FROM pnl;

-- ============================================================
-- 17. Cost Center Spending Analysis
-- Purpose: Find the largest P&L cost centers.
-- ============================================================
SELECT
    cost_center,
    currency,
    -SUM(signed_amount) AS total_expense
FROM vw_financial_actuals
WHERE financial_category IN ('COGS', 'PERSONNEL', 'OPEX', 'DEPRECIATION')
  AND cost_center IS NOT NULL
GROUP BY cost_center, currency
ORDER BY total_expense DESC;

-- ============================================================
-- 18. Profit Center Revenue Analysis
-- Purpose: Compare revenue generated across profit centers.
-- ============================================================
SELECT
    profit_center,
    fiscal_year,
    currency,
    -SUM(signed_amount) AS revenue
FROM vw_financial_actuals
WHERE financial_category = 'REVENUE'
GROUP BY profit_center, fiscal_year, currency
ORDER BY fiscal_year, revenue DESC;

-- ============================================================
-- 19. Accounting Document Reconciliation
-- Purpose: Verify that debit and credit amounts balance at document level.
-- ============================================================
WITH document_totals AS (
    SELECT
        company_code,
        fiscal_year,
        document_number,
        SUM(CASE WHEN debit_credit = 'S'
                 THEN local_currency_amount ELSE 0 END) AS debit_amount,
        SUM(CASE WHEN debit_credit = 'H'
                 THEN local_currency_amount ELSE 0 END) AS credit_amount
    FROM vw_financial_actuals
    GROUP BY company_code, fiscal_year, document_number
)
SELECT
    *,
    credit_amount - debit_amount AS balance_difference
FROM document_totals
ORDER BY ABS(credit_amount - debit_amount) DESC;

-- ============================================================
-- 20. Reconciliation Rate KPI
-- Purpose: Calculate the percentage of documents that balance.
-- ============================================================
WITH document_totals AS (
    SELECT
        company_code,
        fiscal_year,
        document_number,
        SUM(CASE WHEN debit_credit = 'S'
                 THEN local_currency_amount ELSE 0 END) AS debit_amount,
        SUM(CASE WHEN debit_credit = 'H'
                 THEN local_currency_amount ELSE 0 END) AS credit_amount
    FROM vw_financial_actuals
    GROUP BY company_code, fiscal_year, document_number
)
SELECT
    COUNT(*) AS total_documents,
    SUM(CASE WHEN ABS(debit_amount - credit_amount) < 0.01
             THEN 1 ELSE 0 END) AS balanced_documents,
    100.0 *
    SUM(CASE WHEN ABS(debit_amount - credit_amount) < 0.01
             THEN 1 ELSE 0 END) / COUNT(*) AS reconciliation_rate_pct
FROM document_totals;

-- ============================================================
-- 21. Budget and Forecast Version Inspection
-- Purpose: Understand which planning versions are available.
-- ============================================================
SELECT *
FROM plan_versions
ORDER BY fiscal_year, fiscal_month, company_code;

-- ============================================================
-- 22. Budget Variance Formula
-- Purpose: Calculate Actual minus Budget and variance percentage after actuals and budget have been aligned at the same grain.
-- ============================================================
SELECT
    company_code,
    fiscal_year,
    fiscal_month,
    currency,
    actual_revenue,
    budget_revenue,
    actual_revenue - budget_revenue AS revenue_variance,
    100.0 * (actual_revenue - budget_revenue)
        / NULLIF(budget_revenue, 0) AS revenue_variance_pct
FROM actual_budget_monthly
ORDER BY company_code, fiscal_year, fiscal_month;

-- ============================================================
-- 23. Operating Profit Budget Variance
-- Purpose: Compare actual and budgeted operating profit.
-- ============================================================
SELECT
    company_code,
    fiscal_year,
    fiscal_month,
    currency,
    actual_operating_profit,
    budget_operating_profit,
    actual_operating_profit - budget_operating_profit
        AS operating_profit_variance
FROM actual_budget_monthly
ORDER BY company_code, fiscal_year, fiscal_month;

-- ============================================================
-- 24. Year-over-Year Revenue Growth
-- Purpose: Measure how revenue changes versus the previous year.
-- ============================================================
WITH annual_revenue AS (
    SELECT
        company_code,
        fiscal_year,
        currency,
        -SUM(signed_amount) AS revenue
    FROM vw_financial_actuals
    WHERE financial_category = 'REVENUE'
    GROUP BY company_code, fiscal_year, currency
),
comparison AS (
    SELECT
        *,
        LAG(revenue) OVER (
            PARTITION BY company_code, currency
            ORDER BY fiscal_year
        ) AS previous_year_revenue
    FROM annual_revenue
)
SELECT
    *,
    100.0 * (revenue - previous_year_revenue)
        / NULLIF(previous_year_revenue, 0) AS yoy_growth_pct
FROM comparison;

-- ============================================================
-- 25. Rolling 3-Month Revenue
-- Purpose: Smooth monthly fluctuations and observe short-term revenue direction.
-- ============================================================
WITH monthly_revenue AS (
    SELECT
        company_code,
        fiscal_year,
        fiscal_month,
        currency,
        -SUM(signed_amount) AS revenue
    FROM vw_financial_actuals
    WHERE financial_category = 'REVENUE'
    GROUP BY company_code, fiscal_year, fiscal_month, currency
)
SELECT
    *,
    AVG(revenue) OVER (
        PARTITION BY company_code, currency
        ORDER BY fiscal_year, fiscal_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3_month_revenue
FROM monthly_revenue;

-- ============================================================
-- 26. Largest Transactions for Investigation
-- Purpose: Identify unusually large transactions for finance review.
-- ============================================================
SELECT
    company_code,
    fiscal_year,
    fiscal_month,
    document_number,
    gl_account,
    financial_category,
    cost_center,
    profit_center,
    currency,
    local_currency_amount
FROM vw_financial_actuals
ORDER BY local_currency_amount DESC
LIMIT 100;

-- ============================================================
-- 27. Statistical Amount Thresholds in SQL
-- Purpose: Calculate basic amount-distribution information before anomaly modeling.
-- ============================================================
SELECT
    financial_category,
    currency,
    COUNT(*) AS transaction_count,
    AVG(local_currency_amount) AS average_amount,
    MIN(local_currency_amount) AS minimum_amount,
    MAX(local_currency_amount) AS maximum_amount
FROM vw_financial_actuals
GROUP BY financial_category, currency
ORDER BY financial_category, currency;

-- ============================================================
-- 28. Missing Cost Center by Financial Category
-- Purpose: Show whether cost-center missingness is random or structurally related to account type.
-- ============================================================
SELECT
    financial_category,
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN cost_center IS NULL THEN 1 ELSE 0 END)
        AS missing_cost_center,
    100.0 *
    SUM(CASE WHEN cost_center IS NULL THEN 1 ELSE 0 END)
        / COUNT(*) AS missing_cost_center_pct
FROM vw_financial_actuals
GROUP BY financial_category
ORDER BY missing_cost_center_pct DESC;

-- ============================================================
-- 29. Top G/L Accounts by Amount
-- Purpose: Identify financially significant accounts within each currency.
-- ============================================================
SELECT
    gl_account,
    gl_account_name,
    financial_category,
    currency,
    SUM(local_currency_amount) AS total_amount,
    COUNT(*) AS transaction_count
FROM vw_financial_actuals
GROUP BY
    gl_account, gl_account_name,
    financial_category, currency
ORDER BY total_amount DESC;

-- ============================================================
-- 30. Monthly Transaction Volume
-- Purpose: Check accounting activity volume over time.
-- ============================================================
SELECT
    company_code,
    fiscal_year,
    fiscal_month,
    COUNT(*) AS transaction_count,
    COUNT(DISTINCT document_number) AS document_count
FROM vw_financial_actuals
GROUP BY company_code, fiscal_year, fiscal_month
ORDER BY company_code, fiscal_year, fiscal_month;

-- ============================================================
-- 33. Suggested SQL File Structure for GitHub
-- ============================================================
sql/
├── 01_database_setup.sql
├── 02_data_quality.sql
├── 03_financial_view.sql
├── 04_revenue_analysis.sql
├── 05_expense_analysis.sql
├── 06_profitability_analysis.sql
├── 07_budget_variance.sql
├── 08_reconciliation.sql
└── 09_advanced_analysis.sql
