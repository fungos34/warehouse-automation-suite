let cart = {};
let addressConfirmed = false;
let carrierConfirmed = false;
let pendingBuy = false;
let pendingCart = {};


async function loadItems() {
    try {
        const resp = await fetch('/items?all=1');
        if (!resp.ok) throw new Error('Could not load items');
        const items = await resp.json();
        if (!Array.isArray(items)) throw new Error('Invalid items data');
        window.loadedItems = items;
        // Only display items that are sellable
        const sellableItems = items.filter(item => item.is_sellable === 1 || item.is_sellable === true);
        const itemList = document.getElementById('item-list');
        if (sellableItems.length === 0) {
            itemList.innerHTML = '<span style="color:red">No sellable items available.</span>';
            return;
        }
        itemList.innerHTML = '<ul>' + sellableItems.map(item => `
            <li>
            <b>${item.name}</b> (${item.sku})<br>
            ${item.sales_price} ${item.sales_currency_code}
            <button onclick="addToCart(${item.id}, '${item.name}', ${item.sales_price}, '${item.sales_currency_code}', ${item.sales_currency_id || 1}, ${item.cost || 0}, ${item.cost_currency_id || item.sales_currency_id || 1})">Add to Cart</button>
            </li>
        `).join('') + '</ul>';
    } catch (e) {
        document.getElementById('item-list').innerHTML = `<span style="color:red">Error loading items: ${e.message}</span>`;
    }
};

function renderCart() {
    const cartList = document.getElementById('cart-list');
    if (Object.keys(cart).length === 0) {
        cartList.innerHTML = '<i>Cart is empty</i>';
        return;
    }
    let total = 0;
    cartList.innerHTML = `
        <table>
            <thead>
                <tr>
                    <th>Item</th><th>Price</th><th>Qty</th><th>Subtotal</th><th>Actions</th>
                </tr>
            </thead>
            <tbody>
                ${Object.values(cart).map(item => {
                    const subtotal = item.price * item.qty;
                    total += subtotal;
                    return `
                        <tr>
                            <td>${item.name}</td>
                            <td>${item.price} ${item.currency}</td>
                            <td>
                                <input type="number" min="1" value="${item.qty}" style="width:40px" onchange="updateCartQty(${item.id}, this.value)">
                            </td>
                            <td>${subtotal.toFixed(2)} ${item.currency}</td>
                            <td class="cart-actions">
                                <button onclick="removeFromCart(${item.id})">Remove</button>
                            </td>
                        </tr>
                    `;
                }).join('')}
            </tbody>
        </table>
        <div style="text-align:right;font-weight:bold;">Total: ${total.toFixed(2)} ${Object.values(cart)[0].currency}</div>
    `;
}

document.querySelectorAll('input[name="delivery"]').forEach(el => {
    el.onchange = function() {
        document.getElementById('pickup-address').style.display = this.value === 'pickup' ? 'block' : 'none';
        if (this.value === 'ship') {
            document.getElementById('pick-pack').checked = true;
            document.getElementById('pick-pack').disabled = false;
            document.getElementById('split-parcel').disabled = false;
        } else {
            document.getElementById('pick-pack').disabled = false;
            document.getElementById('split-parcel').disabled = !document.getElementById('pick-pack').checked;
        }
    };
document.getElementById('pick-pack').onchange = function() {
    if (document.querySelector('input[name="delivery"]:checked').value !== 'ship') {
        document.getElementById('split-parcel').disabled = !this.checked;
    }
    if (document.querySelector('input[name="delivery"]:checked').value === 'ship') {
        this.checked = true;
    }
};
});


document.getElementById('billing-different').onchange = function() {
    document.getElementById('billing-fields').style.display = this.checked ? 'block' : 'none';
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

// Store quotation/order and partner info for later confirmation
let currentOrder = null;
let currentPartner = null;

document.getElementById('partner-form').onsubmit = async function(e) {
    e.preventDefault();
    if (!pendingBuy) return;
    addressConfirmed = false;
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

    // Only show shipping/carrier if ship to address is selected
    if (document.querySelector('input[name="delivery"]:checked').value === 'ship') {
        await fetchShippingRates();
        shippingOptionsDiv.style.display = 'block';
        document.getElementById('confirm-carrier-btn').style.display = 'inline-block';
        document.getElementById('partner-error').textContent = 'Please select and confirm a carrier.';
        addressConfirmed = true;
        // Check if both confirmed
        updateConfirmPayBtn();
    } else {
        shippingOptionsDiv.style.display = 'none';
        document.getElementById('confirm-carrier-btn').style.display = 'none';
        addressConfirmed = true;
        updateConfirmPayBtn();
    }
    pendingBuy = false;
    return;

    try {
        // 1. Create partner
        const resp = await fetch('/partners', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(partner)
        });
        const partnerData = await resp.json();
        if (!resp.ok) throw new Error(partnerData.detail || 'Failed to create customer');
        currentPartner = partnerData;
        // Ensure email is always present for Stripe checkout
        currentPartner.email = partner.email;
        // 2. Create sale order
        const orderResp = await fetch('/quotations/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ partner_id: partnerData.id, code: '' })
        });
        const order = await orderResp.json();
        if (!orderResp.ok) throw new Error(order.detail || 'Failed to create quotation');
        currentOrder = order;
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

        if (selectedShippingRate) {
            lines.push({
                quantity: 1,
                item_id: 4, // or 0, or a dedicated shipping item in your DB
                price: parseFloat(selectedShippingRate.amount),
                currency_id: 1, // or map currency code to your currency_id
                cost: 0,
                cost_currency_id: 1,
                carrier_id: selectedShippingRate.provider, // store carrier info
                servicelevel: selectedShippingRate.servicelevel
            });
        }

        const lineResp = await fetch(`/quotations/${orderId}/lines`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(lines)
        });
        if (!lineResp.ok) throw new Error('Failed to add quotation lines');

        // 4. Fetch PDF and show preview BEFORE confirming
        const pdfResp = await fetch(`/quotations/${orderId}/print`, { method: 'GET' });
        if (pdfResp.ok) {
            const blob = await pdfResp.blob();
            const url = window.URL.createObjectURL(blob);
            let previewDiv = document.getElementById('quotation-preview');
            if (!previewDiv) {
                previewDiv = document.createElement('div');
                previewDiv.id = 'quotation-preview';
                document.body.appendChild(previewDiv);
            }
            previewDiv.innerHTML = `
                <iframe src="${url}" width="100%" height="400px"></iframe>
                <button id="confirm-pay-btn">Place Order (Payment Required)</button>
            `;
            setTimeout(() => {
                const btn = document.getElementById('confirm-pay-btn');
                if (btn) {
                    btn.onclick = async function() {
                        // 1. Confirm the quotation
                        const confirmResp = await fetch(`/quotations/${orderId}/confirm`, {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' }
                        });
                        if (!confirmResp.ok) {
                            document.getElementById('buy-result').textContent = 'Failed to confirm quotation';
                            return;
                        }
                        // 2. Proceed to payment as before
                        if (!currentPartner.email) {
                            document.getElementById('buy-result').textContent = 'Customer email is missing. Cannot proceed to payment.';
                            return;
                        }
                        const checkoutResp = await fetch('/create-checkout-session', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                order_number: currentOrder.code,
                                email: currentPartner.email
                            })
                        });
                        const checkoutData = await checkoutResp.json();
                        if (checkoutResp.ok && checkoutData.checkout_url) {
                            window.location.href = checkoutData.checkout_url; // Redirect to Stripe Checkout
                        } else {
                            document.getElementById('buy-result').textContent = checkoutData.detail || 'Failed to start payment';
                        }
                        // Optionally close overlay here if you want
                        // document.getElementById('customer-form').style.display = 'none';
                        // document.getElementById('customer-form-overlay').style.display = 'none';
                        // Reset cart and hide form
                        cart = {};
                        renderCart();
                        loadItems();
                        document.getElementById('customer-form').style.display = 'none';
                        document.getElementById('customer-form-overlay').style.display = 'none';
                        pendingBuy = false;
                        pendingCart = {};
                        currentOrder = null;
                        currentPartner = null;
                    };
                }
            }, 0);
        }
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

// After address is entered, fetch shipping rates
const shippingOptionsDiv = document.getElementById('shipping-options');
const shippingSelect = document.getElementById('shipping-rate-select');
const shippingInfoDiv = document.getElementById('shipping-rate-info');
let selectedShippingRate = null;

async function fetchShippingRates() {
    shippingOptionsDiv.style.display = 'none';
    shippingSelect.innerHTML = '';
    shippingInfoDiv.textContent = '';
    try {
        const resp = await fetch('/shippo/rates');
        const data = await resp.json();
        if (resp.ok && data.rates && data.rates.length) {
            shippingOptionsDiv.style.display = 'block';
            // Find cheapest rate
            let cheapest = data.rates[0];
            data.rates.forEach(rate => {
                if (parseFloat(rate.amount) < parseFloat(cheapest.amount)) cheapest = rate;
            });
            data.rates.forEach(rate => {
                const option = document.createElement('option');
                option.value = rate.object_id;
                option.textContent = `${rate.provider} - ${rate.servicelevel} (${rate.amount} ${rate.currency})`;
                option.dataset.price = rate.amount;
                option.dataset.currency = rate.currency;
                option.dataset.provider = rate.provider;
                option.dataset.servicelevel = rate.servicelevel;
                shippingSelect.appendChild(option);
            });
            // Select cheapest by default
            for (let i = 0; i < shippingSelect.options.length; i++) {
                if (shippingSelect.options[i].value === cheapest.object_id) {
                    shippingSelect.selectedIndex = i;
                    break;
                }
            }
            selectedShippingRate = {
                object_id: cheapest.object_id,
                amount: cheapest.amount,
                currency: cheapest.currency,
                provider: cheapest.provider,
                servicelevel: cheapest.servicelevel
            };
            shippingInfoDiv.textContent = `Selected: ${selectedShippingRate.provider} - ${selectedShippingRate.servicelevel}, Price: ${selectedShippingRate.amount} ${selectedShippingRate.currency}`;
            document.getElementById('confirm-carrier-btn').disabled = false;
            // Always update quotation preview when rates are loaded
            if (currentOrder && currentOrder.quotation_id) {
                updateQuotationPreview(currentOrder.quotation_id, getCurrentLines());
            }
        } else {
            shippingInfoDiv.textContent = 'No shipping rates available.';
        }
    } catch (e) {
        shippingInfoDiv.textContent = 'Error fetching shipping rates.';
    }
}

// shippingSelect.onchange = function() {
//     const selected = shippingSelect.options[shippingSelect.selectedIndex];
//     if (!selected) {
//         selectedShippingRate = null;
//         shippingInfoDiv.textContent = 'Please select a shipping option.';
//         document.getElementById('confirm-carrier-btn').disabled = true;
//         return;
//     }
//     selectedShippingRate = {
//         object_id: selected.value,
//         amount: selected.dataset.price,
//         currency: selected.dataset.currency,
//         provider: selected.dataset.provider,
//         servicelevel: selected.dataset.servicelevel
//     };
//     shippingInfoDiv.textContent = `Selected: ${selectedShippingRate.provider} - ${selectedShippingRate.servicelevel}, Price: ${selectedShippingRate.amount} ${selectedShippingRate.currency}`;
//     document.getElementById('confirm-carrier-btn').disabled = false;
//     // Always update quotation preview when carrier changes
//     if (currentOrder && currentOrder.quotation_id) {
//         updateQuotationPreview(currentOrder.quotation_id, getCurrentLines());
//     }
// }

document.getElementById('confirm-carrier-btn').onclick = async function() {
    if (!selectedShippingRate) {
        document.getElementById('partner-error').textContent = 'Please select a shipping option.';
        return;
    }
    document.getElementById('partner-error').textContent = '';
    carrierConfirmed = true;
    updateConfirmPayBtn();
    pendingBuy = true;
    pendingCart = { ...cart };
    // Gather partner data again (in case form changed)
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
        currentPartner = partnerData;
        currentPartner.email = partner.email;
        // 2. Create sale order
        const orderResp = await fetch('/quotations/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ partner_id: partnerData.id, code: '' })
        });
        const order = await orderResp.json();
        if (!orderResp.ok) throw new Error(order.detail || 'Failed to create quotation');
        currentOrder = order;
        const orderId = order.quotation_id;
        // 3. Add order lines (cart + shipping)
        const lines = Object.values(pendingCart).map(item => ({
            quantity: item.qty,
            item_id: item.id,
            price: item.price || 0,
            currency_id: item.currency_id || 1,
            cost: item.cost || 0,
            cost_currency_id: item.cost_currency_id || item.currency_id || 1
        }));
        // Fetch shipping item by SKU from backend
        let shippingItem = null;
        try {
            const resp = await fetch('/items/by-sku/SHIP-001');
            if (resp.ok) {
                shippingItem = await resp.json();
            }
        } catch (err) {}
        if (!shippingItem || !shippingItem.id) {
            document.getElementById('partner-error').textContent = 'Shipping item not found.';
            return;
        }
        lines.push({
            quantity: 1,
            item_id: shippingItem.id,
            price: parseFloat(selectedShippingRate.amount),
            currency_id: shippingItem.sales_currency_id || 1,
            cost: 0,
            cost_currency_id: shippingItem.cost_currency_id || shippingItem.sales_currency_id || 1,
            carrier_id: selectedShippingRate.provider,
            servicelevel: selectedShippingRate.servicelevel
        });
        // 4. Update quotation lines and show PDF preview
        await updateQuotationPreview(orderId, lines);
        // Fetch and show the quotation PDF again after confirming carrier
        const pdfResp = await fetch(`/quotations/${orderId}/print`, { method: 'GET' });
        if (pdfResp.ok) {
            const blob = await pdfResp.blob();
            const url = window.URL.createObjectURL(blob);
            let previewDiv = document.getElementById('quotation-preview');
            if (!previewDiv) {
                previewDiv = document.createElement('div');
                previewDiv.id = 'quotation-preview';
                document.body.appendChild(previewDiv);
            }
            previewDiv.innerHTML = `
                <iframe src="${url}" width="100%" height="400px"></iframe>
                <button id="confirm-pay-btn" ${addressConfirmed && carrierConfirmed ? '' : 'disabled'}>Place Order (Payment Required)</button>
            `;
            setTimeout(() => {
                const btn = document.getElementById('confirm-pay-btn');
                if (btn) {
                    btn.disabled = !(addressConfirmed && carrierConfirmed);
                    btn.onclick = async function() {
                        if (!(addressConfirmed && carrierConfirmed)) return;
                        const confirmResp = await fetch(`/quotations/${orderId}/confirm`, {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' }
                        });
                        if (!confirmResp.ok) {
                            document.getElementById('buy-result').textContent = 'Failed to confirm quotation';
                            return;
                        }
                        if (!currentPartner.email) {
                            document.getElementById('buy-result').textContent = 'Customer email is missing. Cannot proceed to payment.';
                            return;
                        }
                        const checkoutResp = await fetch('/create-checkout-session', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                order_number: currentOrder.code,
                                email: currentPartner.email
                            })
                        });
                        const checkoutData = await checkoutResp.json();
                        if (checkoutResp.ok && checkoutData.checkout_url) {
                            window.location.href = checkoutData.checkout_url;
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
                        currentOrder = null;
                        currentPartner = null;
                    };
                }
            }, 0);
        }
    } catch (e) {
        document.getElementById('partner-error').textContent = e.message || 'Error placing order';
    }
};


// Dynamically update quotation preview
// Helper to get current lines including shipping, with currency conversion
function getCurrentLines() {
    const lines = Object.values(cart).map(item => ({
        quantity: item.qty,
        item_id: item.id,
        price: item.price || 0,
        currency_id: item.currency_id || 1,
        cost: item.cost || 0,
        cost_currency_id: item.cost_currency_id || item.currency_id || 1
    }));
    // Fetch shipping item by SKU from loadedItems
    let shippingItem = window.loadedItems ? window.loadedItems.find(i => i.sku === 'SHIP-001') : null;
    if (selectedShippingRate && shippingItem && shippingItem.id) {
        // Convert USD to EUR if needed
        let price = parseFloat(selectedShippingRate.amount);
        let currency = selectedShippingRate.currency;
        if (currency === 'USD') {
            // Use static rate for now, e.g. 1 USD = 0.92 EUR
            price = +(price * 0.92).toFixed(2);
            currency = 'EUR';
        }
        lines.push({
            quantity: 1,
            item_id: shippingItem.id,
            price: price,
            currency_id: shippingItem.sales_currency_id || 1,
            cost: 0,
            cost_currency_id: shippingItem.cost_currency_id || shippingItem.sales_currency_id || 1,
            carrier_id: selectedShippingRate.provider,
            servicelevel: selectedShippingRate.servicelevel
        });
    }
    return lines;
}

async function updateQuotationPreview(orderId, lines) {
    const lineResp = await fetch(`/quotations/${orderId}/lines`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(lines)
    });
    if (!lineResp.ok) {
        document.getElementById('partner-error').textContent = 'Failed to update quotation lines';
        return;
    }
    const pdfResp = await fetch(`/quotations/${orderId}/print`, { method: 'GET' });
    if (pdfResp.ok) {
        const blob = await pdfResp.blob();
        const url = window.URL.createObjectURL(blob);
        let previewDiv = document.getElementById('quotation-preview');
        if (!previewDiv) {
            previewDiv = document.createElement('div');
            previewDiv.id = 'quotation-preview';
            document.body.appendChild(previewDiv);
        }
        previewDiv.innerHTML = `
            <iframe src="${url}" width="100%" height="400px"></iframe>
            <button id="confirm-pay-btn" disabled>Place Order (Payment Required)</button>
        `;
        setTimeout(() => {
            const btn = document.getElementById('confirm-pay-btn');
            if (btn) {
                btn.disabled = !(addressConfirmed && carrierConfirmed);
                btn.onclick = async function() {
                    if (!(addressConfirmed && carrierConfirmed)) return;
                    const confirmResp = await fetch(`/quotations/${orderId}/confirm`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' }
                    });
                    if (!confirmResp.ok) {
                        document.getElementById('buy-result').textContent = 'Failed to confirm quotation';
                        return;
                    }
                    if (!currentPartner.email) {
                        document.getElementById('buy-result').textContent = 'Customer email is missing. Cannot proceed to payment.';
                        return;
                    }
                    const checkoutResp = await fetch('/create-checkout-session', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            order_number: currentOrder.code,
                            email: currentPartner.email
                        })
                    });
                    const checkoutData = await checkoutResp.json();
                    if (checkoutResp.ok && checkoutData.checkout_url) {
                        window.location.href = checkoutData.checkout_url;
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
                    currentOrder = null;
                    currentPartner = null;
                };
            }
        }, 0);
    }
// Helper to enable/disable Place Order button
function updateConfirmPayBtn() {
    const btn = document.getElementById('confirm-pay-btn');
    if (btn) {
        btn.disabled = !(addressConfirmed && carrierConfirmed);
    }
}
// Reset confirmation flags on address or carrier change
['partner-name','partner-email','partner-phone','partner-street','partner-city','partner-zip','partner-country','partner-billing-street','partner-billing-city','partner-billing-zip','partner-billing-country'].forEach(id => {
    const el = document.getElementById(id);
    if (el) {
        el.oninput = function() {
            addressConfirmed = false;
            updateConfirmPayBtn();
            // Do not update quotation preview automatically here
        };
    }
});
shippingSelect.onchange = function() {
    const confirmCarrierBtn = document.getElementById('confirm-carrier-btn');
    const selected = shippingSelect.options[shippingSelect.selectedIndex];
    if (!selected) {
        selectedShippingRate = null;
        shippingInfoDiv.textContent = 'Please select a shipping option.';
        confirmCarrierBtn.style.display = 'inline-block';
        confirmCarrierBtn.disabled = true;
        carrierConfirmed = false;
        updateConfirmPayBtn();
        return;
    }
    selectedShippingRate = {
        object_id: selected.value,
        amount: selected.dataset.price,
        currency: selected.dataset.currency,
        provider: selected.dataset.provider,
        servicelevel: selected.dataset.servicelevel
    };
    shippingInfoDiv.textContent = `Selected: ${selectedShippingRate.provider} - ${selectedShippingRate.servicelevel}, Price: ${selectedShippingRate.amount} ${selectedShippingRate.currency}`;
    confirmCarrierBtn.style.display = 'inline-block';
    confirmCarrierBtn.disabled = false;
    carrierConfirmed = false;
    updateConfirmPayBtn();
    // Do not update quotation preview automatically here
}


};



// Initial load

// Helper to enable/disable Place Order button
function updateConfirmPayBtn() {
    const btn = document.getElementById('confirm-pay-btn');
    if (btn) {
        btn.disabled = !(addressConfirmed && carrierConfirmed);
    }
}

loadItems();
renderCart();