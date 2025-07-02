document.addEventListener("DOMContentLoaded", async function() {
    const orderNumber = document.getElementById('order-number').textContent;
    const detailsDiv = document.getElementById('order-details');
    try {
        const resp = await fetch(`/sale-orders/by-code/${orderNumber}`);
        if (!resp.ok) throw new Error('Order not found');
        const order = await resp.json();
        let html = `<b>Status:</b> ${order.status}<br>`;
        html += `<b>Customer:</b> ${order.partner_name || ''}<br>`;
        html += `<b>Lines:</b><ul>`;
        for (const line of order.lines) {
            html += `<li>${line.quantity} x ${line.item_name} (${line.price} ${line.currency_code})</li>`;
        }
        html += `</ul>`;
        detailsDiv.innerHTML = html;
    } catch (e) {
        detailsDiv.innerHTML = `<span style="color:red">Could not load order: ${e.message}</span>`;
    }

    document.getElementById('download-bill-btn').onclick = function() {
        window.open(`/sale-orders/${order.id}/print-order`, '_blank');
    };

    document.getElementById('create-return-btn').onclick = async function() {
        // You may want to show a modal for selecting lines/quantities
        // Here, we just create a return for the whole order for demo
        const resp = await fetch('/return-orders/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                origin_model: 'sale_order',
                origin_code: orderNumber,
                lines: [] // You may want to let the user select lines/quantities
            })
        });
        if (resp.ok) {
            document.getElementById('return-result').textContent = 'Return order created!';
        } else {
            const data = await resp.json();
            document.getElementById('return-result').textContent = data.detail || 'Failed to create return order';
        }
    };
});