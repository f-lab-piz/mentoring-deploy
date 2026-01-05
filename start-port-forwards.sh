#!/bin/bash

# Kill existing port-forwards for frontend and backend
pkill -f "port-forward.*mentoring-frontend"
pkill -f "port-forward.*mentoring-backend"

# Start new port-forwards
nohup kubectl port-forward svc/mentoring-frontend-dev -n mentoring-dev 8082:80 --address 0.0.0.0 > /tmp/frontend-pf.log 2>&1 &
nohup kubectl port-forward svc/mentoring-backend-dev -n mentoring-dev 8083:8000 --address 0.0.0.0 > /tmp/backend-pf.log 2>&1 &

# Wait a moment for processes to start
sleep 2

echo "Port forwards started:"
echo "- ArgoCD: http://localhost:8081 (via k3d Ingress - already configured)"
echo "- Frontend: http://localhost:8082"
echo "- Backend: http://localhost:8083"
echo ""
echo "Logs:"
echo "- Frontend: /tmp/frontend-pf.log"
echo "- Backend: /tmp/backend-pf.log"
