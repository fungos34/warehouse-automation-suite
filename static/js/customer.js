
let cart = {};
let pendingBuy = false;
let pendingCart = {};


async function loadItems() {
    try {
        const resp = await fetch('/items');
        if (!resp.ok) throw new Error('Could not load items');
        const items = await resp.json();
        if (!Array.isArray(items)) throw new Error('Invalid items data');
        const itemList = document.getElementById('item-list');
        itemList.innerHTML = '<ul>' + items.map(item => `
            <li>
            <b>${item.name}</b> (${item.sku})<br>
            ${item.sales_price} ${item.sales_currency_code}
            <button onclick="addToCart(${item.id}, '${item.name}', ${item.sales_price}, '${item.sales_currency_code}', ${item.sales_currency_id || 1}, ${item.cost || 0}, ${item.cost_currency_id || item.sales_currency_id || 1})">Add to Cart</button>
            </li>
        `).join('') + '</ul>';
    } catch (e) {
        document.getElementById('item-list').innerHTML = `<span style="color:red">Error loading items: ${e.message}</span>`;
    }
}

function renderCart() {
    const cartList = document.getElementById('cart-list');
    if (Object.keys(cart).length === 0) {
    cartList.innerHTML = '<i>Cart is empty</i>';
    return;
    }
    cartList.innerHTML = '<ul>' + Object.values(cart).map(item => `
    <li>
        ${item.name} (${item.price} ${item.currency}) x 
        <input type="number" min="1" value="${item.qty}" style="width:40px" onchange="updateCartQty(${item.id}, this.value)">
        <button onclick="removeFromCart(${item.id})">Remove</button>
    </li>
    `).join('') + '</ul>';
};


document.getElementById('buy-btn').onclick = function() {
    if (Object.keys(cart).length === 0) {
    document.getElementById('buy-result').textContent = 'Cart is empty!';
    return;
    }
    // Show partner form as modal
    document.getElementById('customer-form').style.display = 'block';
    document.getElementById('customer-form-overlay').style.display = 'block';
    // Optionally focus first input
    document.getElementById('partner-name').focus();
    pendingBuy = true;
    pendingCart = { ...cart };
};

document.getElementById('partner-form').onsubmit = async function(e) {
    e.preventDefault();
    if (!pendingBuy) return;
    document.getElementById('partner-error').textContent = '';
    // Gather partner data
    const partner = {
    name: document.getElementById('partner-name').value,
    email: document.getElementById('partner-email').value,
    phone: document.getElementById('partner-phone').value,
    street: document.getElementById('partner-street').value,
    city: document.getElementById('partner-city').value,
    zip: document.getElementById('partner-zip').value,
    country: document.getElementById('partner-country').value,
    billing_street: document.getElementById('partner-billing-street').value,
    billing_city: document.getElementById('partner-billing-city').value,
    billing_zip: document.getElementById('partner-billing-zip').value,
    billing_country: document.getElementById('partner-billing-country').value,
    partner_type: 'customer'
    };
    try {
    // 1. Create partner
    const resp = await fetch('/partners', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(partner)
    });
    const partnerData = await resp.json();
    if (!resp.ok) throw new Error(partnerData.detail || 'Failed to create customer');
    // 2. Create sale order
    const orderResp = await fetch('/quotations/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ partner_id: partnerData.id, code: '' })
    });
    const order = await orderResp.json();
    if (!orderResp.ok) throw new Error(order.detail || 'Failed to create quotation');
    const orderId = order.quotation_id;

    // 3. Add order lines
    const lines = Object.values(pendingCart).map(item => ({
        quantity: item.qty,
        item_id: item.id,
        price: item.price || 0,
        currency_id: item.currency_id || 1,
        cost: item.cost || 0,
        cost_currency_id: item.cost_currency_id || item.currency_id || 1
    }));
    const lineResp = await fetch(`/quotations/${orderId}/lines`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(lines)
    });
    if (!lineResp.ok) throw new Error('Failed to add quotation lines');

    // Confirm the quotation
    const confirmResp = await fetch(`/quotations/${orderId}/confirm`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
    });
    if (!confirmResp.ok) throw new Error('Failed to confirm quotation');

    // 5. Create Stripe Checkout session
    const checkoutResp = await fetch('/create-checkout-session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            order_number: order.code,
            email: partner.email
        })
    });
    const checkoutData = await checkoutResp.json();
    if (checkoutResp.ok && checkoutData.checkout_url) {
        window.location.href = checkoutData.checkout_url; // Redirect to Stripe Checkout
        return;
    } else {
        document.getElementById('buy-result').textContent = checkoutData.detail || 'Failed to start payment';
    }

    cart = {};
    renderCart();
    loadItems();
    document.getElementById('customer-form').style.display = 'none';
    document.getElementById('customer-form-overlay').style.display = 'none';
    pendingBuy = false;
    pendingCart = {};
    } catch (e) {
    document.getElementById('partner-error').textContent = e.message || 'Error placing order';
    }
};

document.getElementById('partner-cancel-btn').onclick = function() {
    document.getElementById('customer-form').style.display = 'none';
    document.getElementById('customer-form-overlay').style.display = 'none';
    pendingBuy = false;
    pendingCart = {};
};


// Example: Call Shippo address creation endpoint and show result
document.getElementById('create-shippo-address-btn').onclick = async function() {
    try {
        const resp = await fetch('/shippo/create-address', {
            method: 'POST',
            // headers: { Authorization: 'Bearer ' + jwtToken }
        });
        const data = await resp.json();
        const downloadBtn = document.getElementById('download-label-btn');
        if (resp.ok && data.transaction.status !== 'ERROR') {
            downloadBtn.innerHTML = "Download Label";
            downloadBtn.href = data.transaction.label_url;
            downloadBtn.target = "_blank";
            downloadBtn.style.display = "inline";
        } else {
            downloadBtn.innerHTML = "";
            downloadBtn.removeAttribute("href");
            downloadBtn.style.display = "none";
            alert('Error creating Shippo address: ' + (JSON.stringify(data)));
        }
    } catch (e) {
        alert('Error creating Shippo address');
    }
};


window.addToCart = function(id, name, price, currency, currency_id, cost, cost_currency_id) {
    if (!cart[id]) cart[id] = { id, name, price, currency, currency_id, cost, cost_currency_id, qty: 0 };
    cart[id].qty += 1;
    renderCart();
};

window.updateCartQty = function(id, qty) {
    if (qty < 1) { removeFromCart(id); return; }
    cart[id].qty = parseInt(qty);
    renderCart();
};

window.removeFromCart = function(id) {
    delete cart[id];
    renderCart();
};

// Initial load
loadItems();
renderCart();