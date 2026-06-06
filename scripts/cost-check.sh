#!/usr/bin/env bash
# cost-check.sh — weekly AWS spend audit
# Run every Sunday. Hard ceiling: USD 9.00/month.
# IAM note: requires ce:GetCostAndUsage permission.
# Add explicitly when AdministratorAccess is scoped down in Month 2.

# Stop immediately if any command fails, if any variable is unset,
# or if any command in a pipeline fails. Prevents silent failures.
set -euo pipefail

# Target region for all AWS operations
REGION="ap-southeast-1"

# Calculate first day of current month and today's date.
# Cost Explorer requires an explicit date range — it won't assume "this month".
START=$(date -d "$(date +%Y-%m-01)" +%Y-%m-%d)
END=$(date +%Y-%m-%d)

echo "=== AWS Cost Explorer: Month-to-Date ==="
echo "Period: ${START} to ${END}"
echo ""

# Pull total month-to-date spend as a single number.
# UnblendedCost = actual cost before any AWS discounts or credits are applied.
# This is the number that matches your real invoice.
aws ce get-cost-and-usage \
  --time-period "Start=${START},End=${END}" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --query 'ResultsByTime[0].Total.UnblendedCost' \
  --output table

echo ""
echo "=== Cost by Service ==="

# Break down spend by individual AWS service.
# Shows all services with any spend — tells you exactly what is costing money.
aws ce get-cost-and-usage \
  --time-period "Start=${START},End=${END}" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output table

echo ""
echo "Hard ceiling: USD 9.00/month. Alert threshold: USD 5.00/month."
