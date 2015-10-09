function bes = beschleunigung(spiel, farbe)
    %Konstanten
    constSafeBorder = 0.005; %collision border around mines
    constGridRadius = 0.005; 
    constNavSecurity = 0.03; %simplify path
    constWayPointReachedRadius = 0.02; %0.01
    constMineProxPenality = 0.0006;
    constCornerBreaking = 0.02;
   
    %statische variablen definieren
    persistent nodeGrid;
    persistent waypointList;
    
    %%Farbe pr�fen und zuweisen
    if strcmp (farbe, 'rot')
        me = spiel.rot;
        enemy = spiel.blau;
    else
        me = spiel.blau;
        enemy = spiel.rot;
    end
    
    %%wird einmal am Anfang ausgef�hrt
    if spiel.i_t==1
        setupNodeGrid()
    end

    checkTankPath()
    
    %%Pfad zur n�chstbesten Tankstelle
    createPathToNextTanke()
    
    %%Beschleunigung berechnen:
    bes=calculateBES();

    
    %%%%%%%%%%%%%%%%%%%%%%%%PathToBes%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    function erg=calculateBES()
        if (numel(waypointList) <= 0)
            erg = -me.ges;
            return;
        end
        
        %acceleration
        corr = vecNorm(waypointList{1}-me.pos)-vecNorm(me.ges);
        dir = vecNorm(waypointList{1}-me.pos);
        erg = dir + corr*5;
        
        %calculate breaking endvelocity
        breakingEndVel = calcBreakingEndVel();
        
        %decelleration
        distanceToWaypoint=norm(waypointList{1}-me.pos);
        breakDistance = calcBreakDistance(norm(me.ges), breakingEndVel);
        if (breakDistance > distanceToWaypoint)
            erg=-dir + corr*5;
        end
        
        %%�berpr�fen, ob Wegpunkt erreicht wurde, dann 1. Punkt l�schen
        if norm(me.pos-waypointList{1}) < constWayPointReachedRadius
            waypointList(1) = [];
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    function erg=calcBreakingEndVel()
        erg = 0;
        
        if (numel(waypointList) <= 1)
            return;
        end
        
        length = norm(waypointList{1} - me.pos);
        lastDir = vecNorm(waypointList{1} - me.pos);
        waypointIndex = 2;
        
        %return values
        globalMinSpeed = 100;
        globalBreakStartPoint = 100;
        
        nullBreakDistance = calcBreakDistance(norm(me.ges), 0);
        while(length < nullBreakDistance && waypointIndex <= numel(waypointList))
            nextDist = norm(waypointList{waypointIndex} - waypointList{waypointIndex-1});
            nextDir = vecNorm(waypointList{waypointIndex} - waypointList{waypointIndex-1});
            angle = acosd(dot(lastDir, nextDir));
            
            %calculate minimal speed
            minSpeed = 0;
            if (angle < 90 && waypointIndex < numel(waypointList))
                minSpeed = constCornerBreaking/sind(angle);
            end
            
            %get the point where i have to start breaking first
            breakStartPoint = length-calcBreakDistance(norm(me.ges), minSpeed);
            if (breakStartPoint < globalBreakStartPoint)
                globalBreakStartPoint = breakStartPoint;
                globalMinSpeed = minSpeed;
            end
            
            length = length + nextDist;
            lastDir = nextDir;
            waypointIndex = waypointIndex +1;
        end
        
        erg = globalMinSpeed;
    end


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    function erg = calcBreakDistance(vel, endvel)
        erg = ((vel)^2 - (endvel)^2)/(2*spiel.bes);
    end
        

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    function setupNodeGrid()
        gridSizeX = round(1/(constGridRadius*2));
        gridSizeY = round(1/(constGridRadius*2));
        
        %create grid
        for x = 1 : gridSizeX+1
            for y = 1 : gridSizeY+1
                worldPos = [constGridRadius*2*x, constGridRadius*2*y];
                gridPos = [x, y];
                nodeGrid(x,y).worldPos = worldPos;
                nodeGrid(x,y).gridPos = gridPos;
                nodeGrid(x,y).isWalkable = isWalkable(worldPos);
                nodeGrid(x,y).hCost = 0;
                nodeGrid(x,y).fCost = 0;
                nodeGrid(x,y).gCost = 0;
                mineCost = 0;
                
                %Je dichter an Mine, desto teurer!
                for i=1:spiel.n_mine
                    if (norm(nodeGrid(x,y).worldPos-spiel.mine(i).pos)-spiel.mine_radius < 0.1)
                        mineCost = mineCost + constMineProxPenality/(norm(nodeGrid(x,y).worldPos-spiel.mine(i).pos)-spiel.mine_radius);
                    end
                end
                
                nodeGrid(x,y).mineCost = mineCost;
            end
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %Kollisionscheck
    function erg=isWalkable(pos)
        erg = true;
        secureSpaceballRadius = constSafeBorder + spiel.spaceball_radius;
        
        %border check
        if (pos(1) > 1-secureSpaceballRadius || pos(1) < secureSpaceballRadius || pos(2) > 1-secureSpaceballRadius || pos(2) < secureSpaceballRadius)
            erg = false;
            return;
        end
        
        %mine check
        for i = 1 : spiel.n_mine
            if (norm(spiel.mine(i).pos-pos) < spiel.mine(i).radius+secureSpaceballRadius)
                erg = false;
                return;
            end
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %Pathfinder
    function waypoints = findPath(startp, endp)
        pathSuccess = false; % - Pfad gefunden
        
        startPos = getValidNodePos(worldPosToGridPos(startp));
        endPos = getValidNodePos(worldPosToGridPos(endp));
        
        openSet = {startPos};
        closedSet = {};
        closedSetIndex = 1;
        
        startNode = nodeFromGridCoords(startPos);
        endNode = nodeFromGridCoords(endPos);
        
        %if start and end node is invalid - abort
        if (~startNode.isWalkable || ~endNode.isWalkable)
            waypoints = [];
            disp('findPath: invalid start or end position');
            return;
        end
        
        %find path...
        while(numel(openSet) > 0)
            currentNode = nodeFromGridCoords(openSet{1});
            openSetIndex = 1;
            
            %get node woth lowest fcost (or hcost) and remove it from openlist
            for i=1:numel(openSet)
                cn = nodeFromGridCoords(openSet{i});
                if (cn.fCost < currentNode.fCost || cn.fCost == currentNode.fCost && cn.hCost < currentNode.hCost)
                    currentNode = nodeFromGridCoords(openSet{i});    
                    openSetIndex = i;
                end
            end
            
            %remove node from open set
            openSet(openSetIndex) = [];
            %add node to closed set
            closedSet{closedSetIndex} = currentNode.gridPos;
            closedSetIndex = closedSetIndex + 1;
            
            %if it is target - close - path found!
            if (currentNode.gridPos == endPos)
                pathSuccess = true;
                break;
            end
            
            %calculate neighbour cost indices
            neighbours = getNeighbourNodes(currentNode);
            for i = 1 : numel(neighbours)
                neighbour = neighbours(i);
                if (~neighbour.isWalkable || containsNode(closedSet, neighbour.gridPos))
                    continue;
                end
                
                %update costs for neighbours
                movementCostToNeighbour = currentNode.gCost + norm(currentNode.worldPos - neighbour.worldPos);
                if (movementCostToNeighbour < neighbour.gCost || ~containsNode(openSet, neighbour.gridPos))
                    
                    nodeGrid(neighbour.gridPos(1), neighbour.gridPos(2)).gCost = movementCostToNeighbour;
                    nodeGrid(neighbour.gridPos(1), neighbour.gridPos(2)).hCost = norm(endp - neighbour.worldPos);
                    nodeGrid(neighbour.gridPos(1), neighbour.gridPos(2)).fCost = movementCostToNeighbour + norm(endp - neighbour.worldPos) + neighbour.mineCost;
                    nodeGrid(neighbour.gridPos(1), neighbour.gridPos(2)).parent = currentNode.gridPos;

                    %add neighbour to openSet
                    if (~containsNode(openSet, neighbour.gridPos))
                        insertIndex = numel(openSet)+1;
                        openSet{insertIndex} = neighbour.gridPos;
                    end
                end
            end
        end
        
        %finished pathfinding
        if (pathSuccess)
            %retrace path
            currentNode = nodeFromGridCoords(endPos);
            waypoints = [];
            waypointIndex = 1;
            
            while (currentNode.gridPos ~= startPos)
               waypoints{waypointIndex} = currentNode.worldPos;
               waypointIndex = waypointIndex + 1;
               currentNode = nodeFromGridCoords(currentNode.parent);
            end
            
            %flip waypoints
            waypoints = simplifyPath(fliplr(waypoints));
        else
            waypoints = [];
        end
    end


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % if node is not walkable, check for valid node in neighbours
    function erg = getValidNodePos(gridPos)
        node = nodeFromGridCoords(gridPos);
        erg = gridPos;
        
        %nothing to do
        if (node.isWalkable)
            return;
        end
        
        %check neighbours
        neighbours = getNeighbourNodes(node);
        for i = 1 : numel(neighbours)
            neighbour = neighbours(i);
            
            if (neighbour.isWalkable)
                erg = neighbour.gridPos;
                return;
            end
        end
        
        
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    function erg = worldPosToGridPos(pos)
        erg = [round(pos(1)/constGridRadius/2), round(pos(2)/constGridRadius/2)];
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    function erg = nodeFromGridCoords(pos)
        erg = nodeGrid(pos(1), pos(2));
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %check if nodes are equal
    function erg = equalsNode(a, b)
        erg = false;
        if (a.gridPos(1) == b.gridPos(1) && a.gridPos(2) == b.gridPos(2))
            erg = true;
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %get node neighbours
    function erg = getNeighbourNodes(node)
        gridSizeX = round(1/(constGridRadius*2));
        gridSizeY = round(1/(constGridRadius*2));
        
        i = 1;
        for x = node.gridPos(1) -1 : node.gridPos(1) +1
            for y = node.gridPos(2) -1 : node.gridPos(2) + 1
                %check if grid coors are valid
                if (x >= 1 && x <= gridSizeX && y >= 1 && y <= gridSizeY)
                
                    if (equalsNode(nodeGrid(x, y), node))
                        continue;
                    end

                    erg(i) = nodeGrid(x, y);
                    i = i + 1;
                end
            end
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % simplify path
    function erg = simplifyPath(path)
        
        erg = path;
        if (numel(path) <= 1)
            return;
        end
        
        %check collision tube
        for i=fliplr(1:numel(path))
            if (~corridorColliding(path{i}, path{1}, constNavSecurity) || ... 
                    i == 2)
                %no collision detected start to end
                erg = {path{1}, path{i}};
                endIndex = numel(path);
                erg = appendToArray(erg, simplifyPath(path(i+1:endIndex)));
                return;
            end
        end
    end


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %check if array contains node
    function erg = containsNode(nodes, pos)
        erg = false;
        
        for i=1:numel(nodes)
            if (nodes{i}(1) == pos(1) && nodes{i}(2) == pos(2))
                erg = true;
                return;
            end
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %normalize 2D vector
    function erg = vecNorm(vec)
        n = norm(vec);
        erg = [vec(1)/n, vec(2)/n];
        
        if (n == 0)
            erg = [0 , 0];
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %append to existing cell arrray
    function erg = appendToArray(array1, array2)
        array1index = numel(array1)+1;
        erg = array1;
        
        for i=1 : numel(array2)
            erg{array1index} = array2{i};
            array1index = array1index + 1;
        end
    end
    
%%%Search for nearest Tanken and create Path between them
    function createPathToNextTanke()
        if numel(waypointList)<=1 && spiel.n_tanke>=1
            tankdistance=createTankEvaluation(me.pos);
            next_tanke = tankdistance(1,1);
            waypointList = appendToArray(waypointList,findPath(me.pos, spiel.tanke(next_tanke).pos));
            debugDRAW();
        end
    end

%%%%%%%%%%%%%
%create Tank Distance Table
    function erg=createTankEvaluation(position)

        erg = zeros(spiel.n_tanke,4);
        for i=1:spiel.n_tanke
            erg(i,1) = i;                                   %Spalte 1: Tankstellennummer
            erg(i,2) = norm(spiel.tanke(i).pos-position);   %Spalte 2: Entfernung zu "position"
            erg(i,3) = norm(spiel.tanke(i).pos-enemy.pos);  %Spalte 3: Entfernung zum Gegner
            a=-1;
            for j=1:spiel.n_tanke
                if i==j
                    continue
                end
                a=a+1/norm(spiel.tanke(i).pos-spiel.tanke(j).pos);
            end
            erg(i,4) = a*0.4+(1/erg(i,2))-0.5*(1/erg(i,3));                                   %Spalte 4: Anzahl Tankstellen in der N�he und deren Dichte und deren Dichte zum Gegner
        end
        erg=sortrows(erg,[-4 2 -3 1])
    end

    function checkTankPath()
        %%Tankstellenliste Aktualisieren
        endIndex=numel(waypointList);
        if endIndex >= 1
            lastWayPoint=waypointList{endIndex};
            for i=1:spiel.n_tanke
                if norm(spiel.tanke(i).pos-lastWayPoint) <= spiel.tanke_radius+constGridRadius
                    return
                end
            end
            waypointList=[];
        end 
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %corridor colliding
    function erg = corridorColliding(startp, endp, radius)
        length = 0;
        dir = vecNorm(endp-startp);
        erg = false;
        
        while(length < norm(startp - endp))
            pos = startp + dir*length;
            for i = 1:spiel.n_mine
                if (norm(pos-spiel.mine(i).pos)-spiel.mine_radius < radius)
                    erg = true;
                    return;
                end
            end
            length = length + radius/2;
        end
    end

%%%%%%%%%DEBUGGING%%%%%%%
    function debugDRAW()
        for i = 1 : numel(waypointList)
            rectangle ('Parent', spiel.spielfeld_handle, 'Position', [waypointList{i}-0.0025, 0.005, 0.005], 'Curvature', [1 1], 'FaceColor', spiel.farbe.rot, 'EdgeColor', 'none');
        end
    end
end