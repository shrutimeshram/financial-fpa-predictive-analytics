# Financial Performance & FP&A Predictive Analytics

End-to-end FP&A analytics project on SAP-style financial transaction data. It covers data validation, P&L construction, budget and forecast variance analysis, machine-learning revenue forecasting and Isolation Forest anomaly detection, presented in a 4-page Power BI dashboard.

**Tools:** Python (Pandas, Scikit-learn) · MySQL · Power BI (DAX)

## Dataset

SAP-style FP&A dataset (ACDOCA universal journal with G/L, cost center and profit center master data, plus Budget and Rolling Forecast plan versions).

| Area | Value |
|---|---|
| Accounting transaction lines | 159,934 |
| Accounting documents | 79,967 |
| Company codes | 1000, 2000, 3000 |
| Fiscal years | 2022 – 2025 |
| Currencies | EUR, USD, INR |

Source: SAP FP&A dataset by Ajay Kumar, [doi.org/10.5281/zenodo.21888240](https://doi.org/10.5281/zenodo.21888240) (data licensed CC BY 4.0). The large raw transaction files are not stored in this repository; download them from the source.

## Workflow

1. **Data cleaning and validation:** renamed SAP fields, checked missing values and duplicates, created signed amounts (debit positive, credit negative), and reconciled debit/credit at document level.
2. **Financial classification and P&L:** mapped G/L accounts to Revenue, COGS, Personnel, OPEX, Depreciation and Balance Sheet; built monthly Gross Profit, Operating Profit and margins.
3. **Budget and variance analysis:** Actual vs Budget and Rolling Forecast at monthly and component level.
4. **Revenue forecasting:** Random Forest Regressor with lag-1, lag-2, lag-3 and lag-12 features. Chronological split with 2025 as the 12-month test period. Evaluated with MAE, RMSE and MAPE.
5. **Anomaly detection:** Isolation Forest (1% contamination) using transaction amount, financial category and debit/credit context.
6. **SQL analysis (MySQL):** data-quality checks, reusable financial view, revenue, profitability, variance and expense queries.
7. **Power BI dashboard:** Executive FP&A, Budget & Variance, Forecast & ML, Financial Anomaly Detection.

## Key Results

| Metric | Result |
|---|---|
| Document-level debit/credit reconciliation | 100% |
| ML revenue forecast MAPE (2025) | 6.27% |
| Rolling forecast MAPE (same period) | 5.69% |
| Potential unusual transactions flagged | 1,578 (0.99%) |

The lag-12 feature had the highest importance, which points to a strong year-over-year pattern. Anomaly flags are candidates for finance review, not proof of error or fraud.

## Repository Structure

```
notebooks/   Python analysis, forecasting and anomaly detection notebook (Kaggle)
sql/         MySQL queries for validation and financial analysis
powerbi/     Power BI report (.pbix) and DAX measures
data/        Analysis outputs and master-data dimension tables
docs/        Full project documentation
```

## Notes

- EUR, USD and INR amounts are not combined, because no FX conversion was applied.
- Feature importance shows model reliance on a feature, not causation.
