#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-cbt-demo}"

echo "=========================================="
echo "Post-Restore Verification"
echo "=========================================="

EXIT_CODE=0

# Check PostgreSQL pod
echo ""
echo "[1/5] Checking PostgreSQL pod..."
POSTGRES_POD=$(kubectl get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POSTGRES_POD" ]; then
    echo "✗ PostgreSQL pod not found"
    EXIT_CODE=1
else
    POD_STATUS=$(kubectl get pod "$POSTGRES_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" == "Running" ]; then
        echo "✓ PostgreSQL pod is running: $POSTGRES_POD"
    else
        echo "✗ PostgreSQL pod is not running (status: $POD_STATUS)"
        EXIT_CODE=1
    fi
fi

# Check database connectivity
echo ""
echo "[2/5] Checking database connectivity..."
if kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- pg_isready -U demo &>/dev/null; then
    echo "✓ Database is accepting connections"
else
    echo "✗ Database is not ready"
    EXIT_CODE=1
fi

# Check table existence
echo ""
echo "[3/5] Checking table structure..."
if kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -c "\\d demo_data" &>/dev/null; then
    echo "✓ Table 'demo_data' exists"
else
    echo "✗ Table 'demo_data' not found"
    EXIT_CODE=1
fi

# Check row count
echo ""
echo "[4/5] Checking data integrity..."
CURRENT_ROWS=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -t -c "SELECT COUNT(*) FROM demo_data;" 2>/dev/null | tr -d ' ')

if [ -n "$CURRENT_ROWS" ] && [ "$CURRENT_ROWS" -gt 0 ]; then
    echo "✓ Found $CURRENT_ROWS rows in demo_data table"

    # Verify checksum sample
    echo "  Verifying checksums (sampling 10 rows)..."
    CHECKSUM_ERRORS=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -t -c \
        "SELECT COUNT(*) FROM (
            SELECT * FROM demo_data
            WHERE checksum != md5(data_block::text || content)
            LIMIT 10
         ) AS invalid;" 2>/dev/null | tr -d ' ')

    if [ "$CHECKSUM_ERRORS" == "0" ]; then
        echo "  ✓ Checksum validation passed"
    else
        echo "  ✗ Found $CHECKSUM_ERRORS checksum mismatches"
        EXIT_CODE=1
    fi
else
    echo "✗ No rows found in database"
    EXIT_CODE=1
fi

# Compare with expected state
echo ""
echo "[5/5] Comparing with pre-disaster state..."
if [ -f /tmp/cbt-demo-pre-disaster-rows.txt ]; then
    PRE_DISASTER_ROWS=$(cat /tmp/cbt-demo-pre-disaster-rows.txt)
    echo "  Pre-disaster rows:  $PRE_DISASTER_ROWS"
    echo "  Current rows:       $CURRENT_ROWS"

    if [ "$CURRENT_ROWS" == "$PRE_DISASTER_ROWS" ]; then
        echo "  ✓ Row count matches pre-disaster state"
    elif [ "$CURRENT_ROWS" -lt "$PRE_DISASTER_ROWS" ]; then
        echo "  ⚠ Row count is less than pre-disaster state"
        echo "    This is expected if you restored from an earlier snapshot"
    else
        echo "  ⚠ Row count is greater than pre-disaster state"
        echo "    This is unexpected - investigate further"
    fi
else
    echo "  ℹ Pre-disaster state file not found"
    echo "    Cannot compare row counts"
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="

if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ All verification checks PASSED"
    echo ""
    echo "Restore was successful!"
    echo "  - PostgreSQL is running and healthy"
    echo "  - Database is accessible"
    echo "  - Table structure is correct"
    echo "  - Data integrity verified"
    echo "  - Checksums are valid"
else
    echo "✗ Some verification checks FAILED"
    echo ""
    echo "Please review the errors above and:"
    echo "  1. Check pod logs: kubectl logs -n $NAMESPACE $POSTGRES_POD"
    echo "  2. Describe pod: kubectl describe pod -n $NAMESPACE $POSTGRES_POD"
    echo "  3. Check events: kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
fi

echo ""
echo "Additional verification commands:"
echo "  # Connect to database"
echo "  kubectl exec -it -n $NAMESPACE $POSTGRES_POD -- psql -U demo -d cbtdemo"
echo ""
echo "  # Check table size"
echo "  kubectl exec -n $NAMESPACE $POSTGRES_POD -- psql -U demo -d cbtdemo -c \\"
echo "    \"SELECT pg_size_pretty(pg_total_relation_size('demo_data'));\""
echo ""
echo "  # View sample data"
echo "  kubectl exec -n $NAMESPACE $POSTGRES_POD -- psql -U demo -d cbtdemo -c \\"
echo "    \"SELECT * FROM demo_data ORDER BY data_block LIMIT 5;\""

exit $EXIT_CODE
