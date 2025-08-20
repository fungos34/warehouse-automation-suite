async function startReturnOrderByCode(originModel, code = null) {
    if (!code) {
        code = prompt(`Enter ${originModel.replace(/_/g, ' ')} code:`);
        if (!code) return;
    }

    let order;
    if (originModel === 'sale_order') {
        order = await fetch(`/sale-orders/by-code/${code}`).then(r => r.json());
    } else if (originModel === 'purchase_order') {
        // Adjust if you have a similar endpoint for purchase orders
        order = await fetch(`/purchase-orders/by-code/${code}`).then(r => r.json());
    } else if (originModel === 'quotation') {
        order = await fetch(`/quotations/${code}`).then(r => r.json());
    } else {
        showConfirmReceiptResult('Unsupported origin model');
        return;
    }

    if (!order || order.status !== 'confirmed') {
        showConfirmReceiptResult('Order not found or not confirmed');
        return;
    }

    // 2. Fetch order lines
    let linesUrl = '';
    if (originModel === 'sale_order') {
        linesUrl = `/sale-orders/${order.id}/lines`;
    } else if (originModel === 'purchase_order') {
        linesUrl = `/purchase-orders/${order.id}/lines`;
    } else {
        showConfirmReceiptResult('Unsupported origin model');
        return;
    }
    const lines = await fetch(linesUrl).then(r => r.json());

    // 3. Build a simple form for return quantities
    let formHtml = `<form id="return-lines-form"><h4>Return Items for ${code}</h4>`;
    lines.forEach((line, idx) => {
        // Use line.item_name and line.lot_name if available, otherwise fallback
        const itemName = line.item_name || `Item ${line.item_id}`;
        const lotInfo = line.lot_name ? ` (Lot: ${line.lot_name})` : (line.lot_id ? ` (Lot: ${line.lot_id})` : '');
        formHtml += `
        <div>
        <label>
            ${itemName}${lotInfo} - Max: ${line.quantity}
            <input type="number" min="0" max="${line.quantity}" value="0" name="qty${idx}">
            <input type="text" name="reason${idx}" placeholder="Reason for return">
        </label>
        </div>
    `;
    });
    formHtml += `
        <div>
            <label>
                <input type="radio" name="return_mode" value="parcel" checked> Ship items in a parcel
            </label>
            <label>
                <input type="radio" name="return_mode" value="individual"> Return items individually
            </label>
        </div>
    `;
    formHtml += `<button type="submit">Submit Return</button></form>`;

    // Show modal
    const modal = document.createElement('div');
    modal.style.position = 'fixed';
    modal.style.top = '50%';
    modal.style.left = '50%';
    modal.style.transform = 'translate(-50%, -50%)';
    modal.style.background = '#fff';
    modal.style.padding = '24px';
    modal.style.zIndex = 3000;
    modal.style.borderRadius = '10px';
    modal.style.boxShadow = '0 4px 32px rgba(0,0,0,0.25)';
    modal.innerHTML = formHtml;
    document.body.appendChild(modal);

    modal.querySelector('#return-lines-form').onsubmit = async function(e) {
        e.preventDefault();
        const returnLines = [];
        lines.forEach((line, idx) => {
            const qty = parseInt(this[`qty${idx}`].value, 10);
            for (let i = 0; i < qty; i++) {
                returnLines.push({
                    item_id: line.item_id,
                    lot_id: line.lot_id || null,
                    quantity: 1,
                    reason: this[`reason${idx}`].value || '',
                    price: line.price
                });
            }
        });
        if (!returnLines.length) {
            showConfirmReceiptResult('No items selected for return.');
            return;
        }
        const ship = this.return_mode.value === 'parcel' ? 1 : 0;
        // 4. Submit return order
        const resp = await fetch('/return-orders/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                origin_model: originModel,
                origin_code: code,
                lines: returnLines,
                ship: ship
            })
        });
        const data = await resp.json();
        if (resp.ok) {
            showConfirmReceiptResult(`Return order ${data.code} created successfully!`);
            document.body.removeChild(modal);
        } else {
            showConfirmReceiptResult(`Error creating return order: ${JSON.stringify(data.detail)}` || 'Unknown error');
        }
        showConfirmReceiptResult(`Return order ${data.code} created successfully!`);
    };
}

async function loadReturnOrders() {
    const div = document.getElementById('return-orders-list');
    if (!div) return;
    const resp = await fetch('/return-orders/', { headers: { 'Content-Type': 'application/json' } });
    const orders = await resp.json();
    if (!orders.length) {
        div.innerHTML = '<i>No return orders.</i>';
        return;
    }
    div.innerHTML = '<ul>' + orders.map(o => `
    <li>
        <b>${o.code}</b>: ${o.origin_model} ${o.origin_id} (${o.status}) - ${o.partner_name}
        <button onclick="confirmReturnOrder(${o.id})">Confirm</button>
        <button onclick="doneReturnOrder(${o.id})">Set Done</button>
        <button onclick="cancelReturnOrder(${o.id})">Cancel</button>
        <button onclick="downloadReturnOrder(${o.id})">Print PDF</button>
        <button onclick="downloadReturnLabel(${o.id}, '${o.code}')">Print Label</button>
        <button onclick="downloadReturnBill(${o.id}, '${o.code}')">Download Refund Bill</button>
    </li>
    `).join('') + '</ul>';
}

async function loadCustomerReturnOrders() {
    const div = document.getElementById('customer-return-orders-list');
    if (!div) return;
    const resp = await fetch('/return-orders/', { headers: { 'Content-Type': 'application/json' } });
    const orders = await resp.json();
    // Optionally filter for this customer if needed
    // const myOrders = orders.filter(o => o.partner_id === currentCustomerId);
    if (!orders.length) {
        div.innerHTML = '<i>No return orders.</i>';
        return;
    }
    div.innerHTML = '<ul>' + orders.map(o => `
    <li>
        <b>${o.code}</b> (${o.status})
        <button onclick="downloadReturnLabel(${o.id}, '${o.code}')">Print Return Label</button>
    </li>
    `).join('') + '</ul>';
}

window.confirmReturnOrder = async function(id) {
    await fetch(`/return-orders/${id}/confirm`, { method: 'POST', headers: { Authorization: 'Bearer ' + jwtToken } });
    loadReturnOrders();
};
window.doneReturnOrder = async function(id) {
    await fetch(`/return-orders/${id}/done`, { method: 'POST', headers: { Authorization: 'Bearer ' + jwtToken } });
    loadReturnOrders();
};
window.cancelReturnOrder = async function(id) {
    await fetch(`/return-orders/${id}/cancel`, { method: 'POST', headers: { Authorization: 'Bearer ' + jwtToken } });
    loadReturnOrders();
};
window.downloadReturnOrder = async function(id) {
    const resp = await fetch(`/return-orders/${id}/print-order`, { headers: { Authorization: 'Bearer ' + jwtToken } });
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ReturnOrder_${id}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

window.downloadReturnLabel = async function(id, code) {
    const resp = await fetch(`/return-orders/${id}/print-label`);
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ReturnOrder_Label_${code || id}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

window.downloadReturnBill = async function(id, code) {
    const resp = await fetch(`/return-orders/${id}/print-bill`, { headers: { Authorization: 'Bearer ' + jwtToken } });
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ReturnOrder_Bill_${code || id}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

document.addEventListener("DOMContentLoaded", async function() {
    const element = document.getElementById('order-number');
    const orderNumber = element ? element.textContent : null;
    const detailsDiv = document.getElementById('order-details');
    let orderId = null;
    if (orderNumber) {
        try {
            const resp = await fetch(`/sale-orders/by-code/${orderNumber}`);
            if (!resp.ok) throw new Error('Order not found');
            const order = await resp.json();
            orderId = order.id;
            let html = `<b>Thank You ${order.partner_name}!</b><br> Your Order will be further processed when the payment has been confirmed by the bank institute.</br><b>Current Status: ${order.status}</b><br>`;
        html += `<iframe src="/sale-orders/${orderId}/print-order" width="100%" height="600px" style="border:1px solid #ccc;margin-top:20px"></iframe>`;
        detailsDiv.innerHTML = html;
    } catch (e) {
        detailsDiv.innerHTML = `<span style="color:red">Could not load order: ${e.message}</span>`;
    }}

    const billBtn = document.getElementById('download-bill-btn');
    if (billBtn) {
        billBtn.onclick = function() {
            window.open(`/sale-orders/${orderId}/print-order`, '_blank');
        };
    };

    const createReturnBtn = document.getElementById('create-return-btn');
    if (createReturnBtn) {
        createReturnBtn.onclick = async function() {
            startReturnOrderByCode('sale_order', orderNumber);
        };
    }
});


document.addEventListener("DOMContentLoaded", function() {
    const confirmBtn = document.getElementById("confirm-receipt-btn");
    if (confirmBtn) {
        confirmBtn.onclick = async function() {
            // Get the order code from the page
            const orderNumber = document.getElementById("order-number").textContent;
            // Fetch the order to get its numeric ID
            const resp = await fetch(`/sale-orders/by-code/${orderNumber}`);
            if (!resp.ok) {
                showConfirmReceiptResult("Order not found");
                return;
            }
            const order = await resp.json();
            const orderId = order.id;
            // Build the correct unbuild order code
            const unbuildOrderCode = `UO_PKG-sale_order-${orderId}`;
            try {
                const confirmResp = await fetch(`/unbuild-orders/${unbuildOrderCode}/confirm-receipt`, {
                    method: "POST"
                });
                const data = await confirmResp.json();
                showConfirmReceiptResult(data.message || "Done!");
                confirmBtn.classList.remove("pending");
                confirmBtn.disabled = true;
            } catch (e) {
                showConfirmReceiptResult("Error confirming receipt");
            }
        };
    }
});

// Example: Call Shippo address creation endpoint and show result
document.getElementById('create-shippo-address-btn').onclick = async function() {
    try {
        const resp = await fetch('/shippo/create-address', {
            method: 'POST',
            // headers: { Authorization: 'Bearer ' + jwtToken }
        });
        const data = await resp.json();
        const downloadBtn = document.getElementById('download-label-btn');
        if (downloadBtn) {
            if (resp.ok && data.transaction.status !== 'ERROR') {
                downloadBtn.innerHTML = "Download Label";
                downloadBtn.href = data.transaction.label_url;
                downloadBtn.target = "_blank";
                downloadBtn.style.display = "inline";
            } else {
                downloadBtn.innerHTML = "";
                downloadBtn.removeAttribute("href");
                downloadBtn.style.display = "none";
                showConfirmReceiptResult('Error creating Shippo address: ' + (JSON.stringify(data)));
            }
        }
    } catch (e) {
        showConfirmReceiptResult('Error creating Shippo address');
    }
};

function showConfirmReceiptResult(message) {
    const popup = document.getElementById("confirm-receipt-popup");
    const msg = document.getElementById("confirm-receipt-message");
    msg.textContent = message;
    popup.style.display = "block";
    if (window.confirmReceiptTimeout) clearTimeout(window.confirmReceiptTimeout);
    window.confirmReceiptTimeout = setTimeout(hideConfirmReceiptResult, 5000);
}

function hideConfirmReceiptResult() {
    const popup = document.getElementById("confirm-receipt-popup");
    popup.style.display = "none";
    const msg = document.getElementById("confirm-receipt-message");
    msg.textContent = "";
    if (window.confirmReceiptTimeout) clearTimeout(window.confirmReceiptTimeout);
}

// Attach close button handler
document.addEventListener("DOMContentLoaded", function() {
    const closeBtn = document.getElementById("confirm-receipt-close");
    if (closeBtn) {
        closeBtn.onclick = hideConfirmReceiptResult;
    }
});


// Only call these if the elements exist (for admin/customer panel)
if (document.getElementById('return-orders-list')) loadReturnOrders();
if (document.getElementById('customer-return-orders-list')) loadCustomerReturnOrders();
