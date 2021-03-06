class Pathfinder {
public:
    static const vector<Vector2> findPath(Nodegrid nodegrid, Vector2 start, Vector2 end) {
        bool foundPath = false;
        Node &startNode = nodegrid.getValidNode(nodegrid.worldPosToGridPos(start));
        Node &endNode = nodegrid.getValidNode(nodegrid.worldPosToGridPos(end));
        
        if (startNode == endNode || !startNode.is_walkable || !endNode.is_walkable) {
            //mexPrintf("Invalid start or end node \n");
            return vector<Vector2>();
        }
        
        Heap<Node> openSet = Heap<Node>();
        openSet.insert(startNode);
        Arraylist<Node> closedSet = Arraylist<Node>();
        
        while(openSet.size() > 0) {
            Node &currentNode = openSet.removeFirst();
            closedSet.insert(currentNode);
            
            if (currentNode == endNode) {
                foundPath = true;
                break;
            }
            
            vector<Node*> nbs = nodegrid.getNeighbours(currentNode);
            for (int i = 0; i < nbs.size(); i++) {
                if (!nbs[i]->is_walkable || closedSet.contains(*nbs[i])) {
                    continue;
                }
                
                float newCostToN = currentNode.gCost + (currentNode.worldPos - nbs[i]->worldPos).magnitude();
                if (newCostToN < nbs[i]->gCost || !openSet.contains(*nbs[i])) {
                    nbs[i]->gCost = newCostToN;
                    nbs[i]->hCost = (end - nbs[i]->worldPos).magnitude();
                    nbs[i]->fCost = nbs[i]->gCost + nbs[i]->hCost + nbs[i]->mineCost;
                    nbs[i]->parent = &currentNode;
                    
                    //mexPrintf("\nNeighbour: [%f, %f] fCost: %f, gCost: %f\n", nbs[i]->gridPos.x, nbs[i]->gridPos.y, nbs[i]->fCost, nbs[i]->gCost);
                    
                    if (!openSet.contains(*nbs[i])) {
                        openSet.insert(*nbs[i]);
                    } else {
                        openSet.sortUp(*nbs[i]);
                    }
                }
            }
        }
        
        if (foundPath) {
            Node &currentNode = endNode;
            vector<Vector2> waypoints = vector<Vector2>();
            
            while (currentNode != startNode) {
                waypoints.push_back(currentNode.worldPos);
                currentNode = *currentNode.parent;
            }
            
            //swap contents
            vector<Vector2> waypoints2 = vector<Vector2>();
            for (int i=waypoints.size()-1; i >= 0; i--) {
                waypoints2.push_back(waypoints[i]);
            }
            
            return waypoints2;
        } else {
            //mexPrintf("Path not found! \n");
            return vector<Vector2>();
        }
    }
};