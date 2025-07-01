let Graph;
let jwtToken = localStorage.getItem('jwtToken') || null;

window.addEventListener('load', function() {
    if (!jwtToken) {
        showLoginModal();
    } else {
        fetchAndRender();
    }
});

async function login(username, password) {
    const resp = await fetch('/login', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({username, password})
    });
    if (!resp.ok) throw new Error('Login failed');
    const data = await resp.json();
    jwtToken = data.access_token;
    localStorage.setItem('jwtToken', jwtToken);
}

// Show login modal if no token
function showLoginModal() {
    document.getElementById('login-modal').style.display = 'block';
}
function hideLoginModal() {
    document.getElementById('login-modal').style.display = 'none';
}

async function fetchWithAuth(url, options = {}) {
    options.headers = options.headers || {};
    if (jwtToken) {
        options.headers['Authorization'] = 'Bearer ' + jwtToken;
    }
    let resp = await fetch(url, options);
    if (resp.status === 401 || resp.status === 403) {
        showLoginModal();
        throw new Error('Not authenticated');
    }
    return resp;
}

// Helper to get zone name for a location (if available)
function getZoneNameForLocation(loc, zones) {
    if (!loc || !zones) return '';
    const zone = zones.find(z => z.id === loc.zone_id || z.code === loc.zone_code);
    return zone ? zone.name || zone.code : (loc.zone_code || '');
}

// Fetch zones as well, and enhance locationMap and node labels
async function fetchAndRender() {
    if (!jwtToken) {
        showLoginModal();
        return;
    }
    const authHeader = { Authorization: 'Bearer ' + jwtToken };
    const [stockResp, movesResp, locationsResp, zonesResp] = await Promise.all([
        fetch('/warehouse-stock', {headers: authHeader}),
        fetch('/move-lines', {headers: authHeader}),
        fetch('/locations', {headers: authHeader}),
        fetch('/zones', {headers: authHeader})
    ]);
    if (stockResp.status === 401 || movesResp.status === 401 || locationsResp.status === 401 || zonesResp.status === 401) {
        jwtToken = null;
        localStorage.removeItem('jwtToken');
        showLoginModal();
        return;
    }
    if (!stockResp.ok || !movesResp.ok || !locationsResp.ok || !zonesResp.ok) {
        throw new Error('Failed to fetch API data');
    }
    const warehouseStock = await stockResp.json();
    const moveLines = await movesResp.json();
    const locations = await locationsResp.json();
    const zones = await zonesResp.json();

    // --- NEW: Render cubes for locations and fill state ---
    
    // Create or update graph FIRST
    if (!Graph) {
    Graph = ForceGraph3D()
        (document.getElementById('3d-graph'))
        .nodeId('id')
        .nodeVal('val')
        .nodeLabel(node => node.label)
        .forceEngine('d3')
        .linkDirectionalArrowLength(3)
        .linkDirectionalArrowRelPos(1)
        .linkWidth(0.5)
        .linkLabel('label')
        .linkColor(link => link.intervention ? 'orange' : (link.status === 'done' ? 'limegreen' : 'red'))
        .linkCurvature(link => link.curvature)
        .linkCurveRotation(link => link.rotation)
        .cameraPosition({ x: 0, y: -90, z: 80 });
    }

    // Remove previous objects (only if Graph is initialized)
    if (window.locationCubes) {
    window.locationCubes.forEach(cube => Graph.scene().remove(cube));
    }
    if (window.fillCubes) {
    window.fillCubes.forEach(cube => Graph.scene().remove(cube));
    }
    window.locationCubes = [];
    window.fillCubes = [];

    // Build stock lookup by location_id
    const stockByLocation = {};
    warehouseStock.forEach(entry => {
    if (entry.location_id == null) return;
    if (!stockByLocation[entry.location_id]) stockByLocation[entry.location_id] = 0;
    if (entry.stock_quantity) stockByLocation[entry.location_id] += entry.stock_quantity;
    });


    // Build location map (including locations with coordinates)
    const locationMap = {};
    const maxStock = Math.max(...Object.values(stockByLocation), 1); // Avoid division by zero

    // Group locations by their original coordinates
    const coordGroups = {};
    locations.forEach(loc => {
        const key = `${loc.x},${loc.y},${loc.z}`;
        if (!coordGroups[key]) coordGroups[key] = [];
        coordGroups[key].push(loc);
    });

    Object.values(coordGroups).forEach(group => {
        if (group.length === 1) {
            // Only one location at this coordinate, keep as is
            const loc = group[0];
            const stock = stockByLocation[loc.id] || 0;
            const normalized = maxStock ? stock / maxStock : 0;
            const minVal = stock === 0 ? 0.02 : 0.05;
            // Find zone name for this location
            let zoneName = '';
            if (loc.zone_code || loc.zone_id) {
                zoneName = getZoneNameForLocation(loc, zones);
            }
            locationMap[loc.id] = {
                id: loc.id.toString(),
                label: zoneName
                    ? `${loc.code}${loc.description ? ' / ' + loc.description : ''} — ${zoneName}`
                    : `${loc.code}${loc.description ? ' / ' + loc.description : ''}`,
                x: loc.x,
                y: loc.y,
                z: loc.z,
                fx: loc.x,
                fy: loc.y,
                fz: loc.z,
                val: Math.max(normalized, minVal)
            };
        } else {
            // Offset the cluster center far from the main warehouse (e.g., +40 on x)
            const offsetX = 10;
            const offsetY = 10;
            const offsetZ = 0;
            const radius = 55; // adjust for more/less separation within the group
            const angleStep = (2 * Math.PI) / group.length;
            group.forEach((loc, i) => {
                const angle = i * angleStep;
                const dx = Math.cos(angle) * radius;
                const dy = Math.sin(angle) * radius;
                const stock = stockByLocation[loc.id] || 0;
                const normalized = maxStock ? stock / maxStock : 0;
                const minVal = stock === 0 ? 0.02 : 0.05;
                let zoneName = '';
                if (loc.zone_code || loc.zone_id) {
                    zoneName = getZoneNameForLocation(loc, zones);
                }
                locationMap[loc.id] = {
                    id: loc.id.toString(),
                    label: zoneName
                        ? `${loc.code}${loc.description ? ' / ' + loc.description : ''} — ${zoneName}`
                        : `${loc.code}${loc.description ? ' / ' + loc.description : ''}`,
                    x: loc.x + dx + offsetX,
                    y: loc.y + dy + offsetY,
                    z: loc.z + offsetZ,
                    fx: loc.x + dx + offsetX,
                    fy: loc.y + dy + offsetY,
                    fz: loc.z + offsetZ,
                    val: Math.max(normalized, minVal)
                };
            });
        }
    });

    const graphNodes = Object.values(locationMap);

    // Deterministic hash function for a string (returns a float between 0 and 1)
    function hashToUnitFloat(str) {
    let hash = 5381;
    for (let i = 0; i < str.length; i++) {
        hash = ((hash << 5) + hash) + str.charCodeAt(i);
    }
    return ((hash >>> 0) % 10000) / 10000;
    }

    // Build links (move lines as arrows)
    const interventionMoveIds = new Set(
    (await fetch('/interventions', { headers: { Authorization: 'Bearer ' + jwtToken } })
        .then(r => r.json()))
        .filter(i => !i.resolved)
        .map(i => i.move_id)
    );

    const graphLinks = moveLines
    .filter(line => line.source_id && line.target_id)
    .map(line => {
        const key = `${line.source_id}-${line.target_id}-${line.id}`;
        const curvature = 0.2 + hashToUnitFloat(key) * 0.3;
        const rotation = hashToUnitFloat(key + 'rot') * 2 * Math.PI;
        return {
        source: line.source_id.toString(),
        target: line.target_id.toString(),
        label: `MoveLine ${line.id}`,
        value: line.quantity || 1,
        status: line.status,
        curvature,
        rotation,
        intervention: interventionMoveIds.has(line.move_id)
        };
    });

    // Create or update graph
    if (!Graph) {
        Graph = ForceGraph3D()
            (document.getElementById('3d-graph'))
            .nodeId('id')
            .nodeVal('val')
            .nodeLabel(node => node.label) // <-- now shows code, description, and zone
            .forceEngine('d3')
            .linkDirectionalArrowLength(3) // arrowhead
            .linkDirectionalArrowRelPos(1)
            .linkWidth(0.5) // line
            .linkLabel('label')
            .linkColor(link => link.intervention ? 'orange' : (link.status === 'done' ? 'limegreen' : 'red'))
            .linkCurvature(link => link.curvature)
            .linkCurveRotation(link => link.rotation)
            .cameraPosition({ x: 0, y: -90, z: 80 });
    }
    Graph.graphData({ nodes: graphNodes, links: graphLinks });

    // Replace node rendering with cubes
    Graph.nodeThreeObject(node => {
    // Find the location for this node
    const loc = locations.find(l => l.id.toString() === node.id);
    if (!loc) return undefined;

    // Outer cube: wireframe, min corner at node position
    const boxGeometry = new THREE.BoxGeometry(loc.dx, loc.dy, loc.dz);
    boxGeometry.translate(loc.dx / 2, loc.dy / 2, loc.dz / 2); // shift so min corner is at (0,0,0)
    const edges = new THREE.EdgesGeometry(boxGeometry);
    const lineMaterial = new THREE.LineBasicMaterial({ color: 0x8888ff });
    const wireframe = new THREE.LineSegments(edges, lineMaterial);

    // Inner cube: fill state (stock), min corner at node position
    const stock = stockByLocation[loc.id] || 0;
    const fillDz = Math.max(0.01, Math.min(1, stock / 100)) * loc.dz;
    const fillGeometry = new THREE.BoxGeometry(loc.dx * 0.95, loc.dy * 0.95, fillDz);
    fillGeometry.translate((loc.dx * 0.95) / 2, (loc.dy * 0.95) / 2, fillDz / 2); // shift so min corner is at (0,0,0)
    const fillMaterial = new THREE.MeshLambertMaterial({ color: 0x44ff44, opacity: 0.7, transparent: true });
    const fillCube = new THREE.Mesh(fillGeometry, fillMaterial);

    // No need to set .position, just add as child
    wireframe.add(fillCube);
    return wireframe;
    });


    // When picking changes, update move lines
    document.getElementById('picking-select').onchange = function() {
    populateMoveLineSelectByPicking(this.value);
    };

    await populateMoveLineSelect();
    await populatePickingSelect();
}



function togglePanel(panelId, btn) {
    const panel = document.getElementById(panelId);
    if (panel.style.display === 'none') {
    panel.style.display = 'block';
    btn.textContent = btn.textContent.replace('Show', 'Hide');
    } else {
    panel.style.display = 'none';
    btn.textContent = btn.textContent.replace('Hide', 'Show');
    }
}

document.getElementById('toggle-customer').onclick = function() {
    togglePanel('customer-panel', this);
};
document.getElementById('toggle-warehouse').onclick = function() {
    togglePanel('warehouse-panel', this);
};
document.getElementById('toggle-inbound').onclick = function() {
    togglePanel('inbound-panel', this);
};
document.getElementById('toggle-sales').onclick = function() {
    togglePanel('sales-panel', this);
};

// Make all .side-panel elements draggable by their .panel-drag-handle
document.querySelectorAll('.side-panel').forEach(panel => {
    const handle = panel.querySelector('.panel-drag-handle') || panel;
    let offsetX = 0, offsetY = 0, startX = 0, startY = 0, dragging = false;

    handle.onmousedown = function(e) {
    dragging = true;
    startX = e.clientX;
    startY = e.clientY;
    // Get current panel position
    const rect = panel.getBoundingClientRect();
    offsetX = startX - rect.left;
    offsetY = startY - rect.top;
    document.body.style.userSelect = 'none';
    };

    document.addEventListener('mousemove', function(e) {
    if (!dragging) return;
    panel.style.left = (e.clientX - offsetX) + 'px';
    panel.style.top = (e.clientY - offsetY) + 'px';
    panel.style.right = 'auto'; // Allow free movement
    panel.style.position = 'absolute';
    });

    document.addEventListener('mouseup', function() {
    dragging = false;
    document.body.style.userSelect = '';
    });
});

// Attach login handler
document.getElementById('login-btn').onclick = async function() {
    const username = document.getElementById('login-username').value;
    const password = document.getElementById('login-password').value;
    try {
        await login(username, password);
        hideLoginModal();
        fetchAndRender();
    } catch (e) {
        document.getElementById('login-error').textContent = 'Login failed!';
    }
};

// Refresh button
document.getElementById('refresh-btn').onclick = fetchAndRender;

// Initial fetch
fetchAndRender();
