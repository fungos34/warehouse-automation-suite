let cart = {};
let cartConfirmed = false;
let addressConfirmed = false;
let carrierConfirmed = false;
let paymentConfirmed = false;


let pendingBuy = false;
let pendingCart = {};

let hasPhysical = false;
let hasDigital = false;
let selectedShippingRate = null;

// Store quotation/order and partner info for later confirmation
let currentOrder = null;
let currentPartner = null;

let partnerErrorTimeout = null;
let buyResultTimeout = null;

let allPickupBookings = [];
let pickupBookingPage = 0;
const pickupBookingPageSize = 6;
let reservedPickupBooking = null;

const SHIPPING_RATE_PAGE_SIZE = 3;
let shippingRatePage = 0;

// ===============================
//  Initialization & DOM Setup
// ===============================

function scrollToSection(sectionId) {
    const el = document.getElementById(sectionId);
    if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
}

async function loadItems() {
    console.log("loading items ...");
    try {
        const resp = await fetch('/items');
        if (!resp.ok) throw new Error('Could not load items');
        const items = await resp.json();
        if (!Array.isArray(items)) throw new Error('Invalid items data');
        window.loadedItems = items;
        // Only display items that are sellable (avoid showing items not for sale)
        const sellableItems = items.filter(item => item.is_sellable === 1 || item.is_sellable === true);
        const itemList = document.getElementById('item-list');
        if (sellableItems.length === 0) {
            itemList.innerHTML = '<span style="color:red">No sellable items available.</span>';
            return;
        }
        renderShopItems(sellableItems);
    } catch (e) {
        document.getElementById('item-list').innerHTML = `<span style="color:red">Error loading items: ${e.message}</span>`;
    }
}


function renderCart() {
    const cartList = document.getElementById('cart-list');
    if (Object.keys(cart).length === 0) {
        cartList.innerHTML = '<div class="cart-empty"><i class="fas fa-shopping-cart"></i> Cart is empty</div>';
        resetCheckoutFlow();
        return;
    }
    let total = 0;
    cartList.innerHTML = `
        <div class="cart-grid">
            ${Object.values(cart).map(item => {
                const subtotal = item.price * item.qty;
                total += subtotal;
                return `
                    <div class="cart-item-card">
                        <div class="cart-item-title">${item.name}</div>
                        <div class="cart-item-meta">
                            <span class="cart-item-sku">SKU: ${item.sku || ''}</span>
                            <span class="cart-item-price">${item.price} ${item.currency}</span>
                        </div>
                        <div class="cart-item-qty">
                            <label for="cart-qty-${item.id}" class="cart-qty-label">Quantity:</label>
                            <input id="cart-qty-${item.id}" type="number" min="1" value="${item.qty}" class="cart-qty-input" onchange="updateCartQty(${item.id}, this.value)">
                        </div>
                        <div class="cart-item-subtotal">Subtotal: ${subtotal.toFixed(2)} ${item.currency}</div>
                        <div class="cart-actions">
                            <button class="cart-remove-btn" onclick="removeFromCart(${item.id})"><i class="fas fa-trash"></i> Remove</button>
                        </div>
                    </div>
                `;
            }).join('')}
        </div>
        <div class="cart-total">Total: <b>${total.toFixed(2)} ${Object.values(cart)[0].currency}</b></div>
    `;
}

// Example for item rendering in returns.js or a new shop.js
function renderShopItems(items) {
    const grid = document.getElementById("item-list");
    grid.innerHTML = "";
    items.forEach(item => {
        grid.innerHTML += `
            <div class="shop-item-card">
                <div class="shop-item-image-wrap">
                    <img class="shop-item-image" src="${item.image_url || '/static/img/placeholder.png'}" alt="${item.name}">
                </div>
                <div class="shop-item-title">${item.name}</div>
                <div class="shop-item-desc">${item.description || '<span style=\"color:#aaa\">No description available.</span>'}</div>
                <div class="shop-item-meta">
                    <span class="shop-item-sku">SKU: ${item.sku}</span>
                    ${item.stock !== undefined ? `<span class="shop-item-stock ${item.stock > 0 ? 'in-stock' : 'out-stock'}">${item.stock > 0 ? 'In stock' : 'Out of stock'}</span>` : ''}
                </div>
                <div class="shop-item-price">${item.sales_price ? '€' + Number(item.sales_price).toFixed(2) : ''}</div>
                <button class="shop-item-add-btn" onclick="addToCart(${item.id}, '${item.name.replace(/'/g, "\\'")}', ${item.sales_price || 0}, '${item.sales_currency_code || ''}', ${item.sales_currency_id || 1}, ${item.cost || 0}, ${item.cost_currency_id || item.sales_currency_id || 1}, '${item.sku || ''}', ${item.is_digital ? 'true' : 'false'})">
                    <i class="fas fa-cart-plus"></i> Add to Cart
                </button>
            </div>
        `;
    });
}

function updatePickupMapLink(name, street, zip, city) {
    const mapLink = document.getElementById('pickup-map-link');
    if (mapLink) {
        // Google Maps link for user convenience
        const query = encodeURIComponent(`${street} ${zip} ${city}`);
        mapLink.href = `https://www.google.com/maps/search/?api=1&query=${query}`;
        mapLink.textContent = "Show on Google Maps";
    }
}


function resetCheckoutFlow() {
    cartConfirmed = false;
    addressConfirmed = false;
    carrierConfirmed = false;
    paymentConfirmed = false;
    // Reset all checkout UI and flags to initial state
    document.getElementById('address-section').style.display = 'none';
    document.getElementById('shipping-section').style.display = 'none';
    document.getElementById('payment-section').style.display = 'none';
    document.getElementById('proceed-checkout-btn').disabled = false;
    document.getElementById('cancel-checkout-btn').disabled = true;

}

function resetAddressConfirmation() {
    // Reset address confirmation when user edits address fields
    addressConfirmed = false;
    shippingConfirmed = false;
    paymentConfirmed = false;
    // document.getElementById('confirm-data-btn').style.display = 'inline-block';
    document.getElementById('confirm-data-btn').disabled = false;
    document.getElementById('cancel-address-btn').disabled = true;
    document.getElementById('shipping-section').style.display = 'none';
    document.getElementById('payment-section').style.display = 'none';
}

function showShippingOptionsIfReady() {
    // Only show shipping options if shipping is selected and address is confirmed
    const delivery = document.querySelector('input[name="delivery"]:checked').value;
    if (delivery === 'ship' && cartConfirmed && addressConfirmed) {
        document.getElementById('shipping-section').style.display = 'block';
        scrollToSection('shipping-section');
    } else if (cartConfirmed && addressConfirmed) {
        document.getElementById('shipping-section').style.display = 'none';
        document.getElementById('payment-section').style.display = 'block';
        scrollToSection('payment-section');
    }
    carrierConfirmed = false;
    paymentConfirmed = false;
}


// Helper to enable/disable Place Order button
function updateConfirmPayBtn() {
    // Only enable pay button if both address and carrier are confirmed
    const btn = document.getElementById('confirm-pay-btn');
    if (btn) {
        if (document.querySelector('input[name="delivery"]:checked').value === 'ship') {
            btn.disabled = !(cartConfirmed && addressConfirmed && carrierConfirmed);
            document.getElementById('cancel-payment-btn').disabled = (cartConfirmed && addressConfirmed && carrierConfirmed);
        } else {
            btn.disabled = !(cartConfirmed && addressConfirmed);
            document.getElementById('cancel-payment-btn').disabled = (cartConfirmed && addressConfirmed);
        }
    }
}

// ===============================
// Cart Management
// ===============================

window.addToCart = function(id, name, price, currency, currency_id, cost, cost_currency_id, sku, is_digital) {
    if (!cart[id]) cart[id] = { id, name, price, currency, currency_id, cost, cost_currency_id, qty: 0, sku, is_digital };
    cart[id].qty += 1;
    renderCart();
    resetCheckoutFlow();
};

window.updateCartQty = function(id, qty) {
    if (qty < 1) { removeFromCart(id); return; }
    cart[id].qty = parseInt(qty);
    renderCart();
    resetCheckoutFlow();
};

window.removeFromCart = function(id) {
    delete cart[id];
    renderCart();
    resetCheckoutFlow();
};

// Helper to check cart contents
function getCartProductTypes() {
    hasDigital = false;
    hasPhysical = false;
    Object.values(cart).forEach(item => {
        // Assume item.is_digital is true for digital products, false/undefined for physical
        if (item.is_digital) hasDigital = true;
        else hasPhysical = true;
    });
    return { hasPhysical, hasDigital };
}


// ===============================
// Address & Partner Data
// ===============================

function syncPartnerFields() {
    const delivery = document.querySelector('input[name="delivery"]:checked').value;
    const billingDifferent = document.getElementById('billing-different').checked;

    // If shipping and billing are NOT different, copy shipping fields to billing fields
    if (delivery === 'ship' && !billingDifferent) {
        document.getElementById('partner-billing-name').value = document.getElementById('partner-name').value;
        document.getElementById('partner-billing-street').value = document.getElementById('partner-street').value;
        document.getElementById('partner-billing-city').value = document.getElementById('partner-city').value;
        document.getElementById('partner-billing-country').value = document.getElementById('partner-country').value;
        document.getElementById('partner-billing-zip').value = document.getElementById('partner-zip').value;
        document.getElementById('partner-billing-email').value = document.getElementById('partner-email').value;
        document.getElementById('partner-billing-phone').value = document.getElementById('partner-phone').value;
        document.getElementById('partner-billing_notes').value = document.getElementById('partner_notes').value;
    }
    // If pickup is selected, copy billing fields to shipping fields
    else if (delivery === 'pickup' || delivery === 'digital') {
        document.getElementById('partner-name').value = document.getElementById('partner-billing-name').value;
        document.getElementById('partner-street').value = document.getElementById('partner-billing-street').value;
        document.getElementById('partner-city').value = document.getElementById('partner-billing-city').value;
        document.getElementById('partner-country').value = document.getElementById('partner-billing-country').value;
        document.getElementById('partner-zip').value = document.getElementById('partner-billing-zip').value;
        document.getElementById('partner-email').value = document.getElementById('partner-billing-email').value;
        document.getElementById('partner-phone').value = document.getElementById('partner-billing-phone').value;
        document.getElementById('partner_notes').value = document.getElementById('partner-billing_notes').value;
    }
}


function getPartnerData() {
    syncPartnerFields();
    const billingDifferent = document.getElementById('billing-different').checked;
    const partner = {
        name: document.getElementById('partner-name').value,
        street: document.getElementById('partner-street').value,
        city: document.getElementById('partner-city').value,
        country: document.getElementById('partner-country').value,
        zip: document.getElementById('partner-zip').value,
        email: document.getElementById('partner-email').value,
        phone: document.getElementById('partner-phone').value,
        notes: document.getElementById('partner_notes').value,
        billing_name: billingDifferent ? document.getElementById('partner-billing-name').value : document.getElementById('partner-name').value,
        billing_street: billingDifferent ? document.getElementById('partner-billing-street').value : document.getElementById('partner-street').value,
        billing_city: billingDifferent ? document.getElementById('partner-billing-city').value : document.getElementById('partner-city').value,
        billing_country: billingDifferent ? document.getElementById('partner-billing-country').value : document.getElementById('partner-country').value,
        billing_zip: billingDifferent ? document.getElementById('partner-billing-zip').value : document.getElementById('partner-zip').value,
        billing_email: billingDifferent ? document.getElementById('partner-billing-email').value : document.getElementById('partner-email').value,
        billing_phone: billingDifferent ? document.getElementById('partner-billing-phone').value : document.getElementById('partner-phone').value,
        billing_notes: document.getElementById('partner-billing_notes').value,
        partner_type: 'customer'
    };
    return partner;
}

function getCompanyData() {
    const company = {
        name: document.getElementById('company-name').value,
        vat_number: document.getElementById('company-vat-number').value,
        logo_url: document.getElementById('company-logo-url').value,
        website: document.getElementById('company-website').value
    };
    return company;
}

async function createCompanyIfChecked(partnerId) {
    if (document.getElementById('is-company').checked) {
        let company = getCompanyData();
        company.partner_id = partnerId;
        const resp = await fetch('/companies', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(company)
        });
        const data = await resp.json();
        if (resp.ok) return data.id;
        throw new Error(data.detail || 'Failed to create company');
    }
    return null;
}


// ===============================
// Checkout Step Handlers
// ===============================


document.getElementById('proceed-checkout-btn').onclick = function() {
    if (Object.keys(cart).length === 0) {
        showBuyResult('Cart is empty!');
        return;
    }

    const { hasPhysical, hasDigital } = getCartProductTypes();

    // Hide all address blocks initially
    document.getElementById('address-section').style.display = 'none';
    document.getElementById('shipping-section').style.display = 'none';
    document.getElementById('payment-section').style.display = 'none';

    // Scenario 1: Only digital products
    if (hasDigital && !hasPhysical) {
        
        document.getElementById('cart-options').style.display = 'block'; // Hide all options
        document.querySelectorAll('.option-group').forEach(group => group.style.display = 'none'); // Hide delivery selection

        document.querySelector('input[name="delivery"][value="digital"]').checked = true; // Set delivery type to digital
        document.getElementById('pickup-address').style.display = 'block';
    }
    // Scenario 2: Only physical products and Scenario 3: Both digital and physical products
    else if ((hasPhysical && !hasDigital) || (hasPhysical && hasDigital)) {
        document.getElementById('cart-options').style.display = 'block';
        document.querySelectorAll('.option-group').forEach(group => group.style.display = 'flex');

        document.querySelector('input[name="delivery"][value="ship"]').checked = true; // Set delivery type to ship
    }

    
    this.disabled = true;
    document.getElementById('cancel-checkout-btn').disabled = false;
    document.getElementById('confirm-data-btn').disabled = false;
    document.getElementById('cancel-address-btn').disabled = true;
    document.getElementById('address-section').style.display = 'block';
    scrollToSection('address-section');

    cartConfirmed = true;
    addressConfirmed = false;
    shippingConfirmed = false;
    paymentConfirmed = false;
    toggleAddressBlocks();
};

// Cancel Proceed to Check-Out
document.getElementById('cancel-checkout-btn').onclick = function() {
    resetCheckoutFlow();
};


document.getElementById('confirm-data-btn').onclick = async function(e) {
    e.preventDefault();

    addressConfirmed = true;
    syncPartnerFields();
    
    // Validate address section required fields
    if (!validateRequiredFields('address-section')) {
        showBuyResult('Please fill in all required address fields.');
        return;
    } else if (Object.keys(cart).length === 0) {
        showPartnerError('Cart is empty!');
        return;
    } else if (!cartConfirmed) {
        showPartnerError('Confirmations missing.');
        return;
    }

    // Gather address data
    const partner = {
        name: document.getElementById('partner-name').value,
        email: document.getElementById('partner-email').value,
        phone: document.getElementById('partner-phone').value,
        street: document.getElementById('partner-street').value,
        city: document.getElementById('partner-city').value,
        zip: document.getElementById('partner-zip').value,
        country: document.getElementById('partner-country').value,
        billing_name: document.getElementById('partner-billing-name').value,
        billing_email: document.getElementById('partner-billing-email').value,
        billing_phone: document.getElementById('partner-billing-phone').value,
        billing_street: document.getElementById('partner-billing-street').value,
        billing_city: document.getElementById('partner-billing-city').value,
        billing_zip: document.getElementById('partner-billing-zip').value,
        billing_country: document.getElementById('partner-billing-country').value,
        partner_type: 'customer'
    };

    // 1. Create partner/customer
    let partnerId = null;
    try {
        const resp = await fetch('/partners', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(partner)
        });
        const data = await resp.json();
        if (resp.ok) partnerId = data.id;
        else throw new Error(data.detail || 'Failed to create customer');
    } catch (e) {
        showPartnerError(e.message);
        return;
    }

    // 1.1. Create company if checked
    let companyId = null;
    try {
        companyId = await createCompanyIfChecked(partnerId);
    } catch (err) {
        showPartnerError(err.message);
        return;
    }

    let deliveryType = document.querySelector('input[name="delivery"]:checked').value;

    // Only book pickup slot if pickup is selected
    if (deliveryType === 'pickup' && reservedPickupBooking) {
        try {
            const resp = await fetch(`/service-bookings/${reservedPickupBooking.id}/book`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ partner_id: partnerId })
            });
            const data = await resp.json();
            if (!resp.ok) throw new Error(data.detail || "Booking failed.");
            showBuyResult("Pickup slot booked!");
            loadAvailableServiceBookings('CC-SLOT-001');
        } catch (e) {
            showPartnerError("Error booking slot: " + e.message);
            return;
        }
    }

    // 2. Create quotation
    const quotationData = {
        partner_id: partnerId,
        code: '',
        currency_id: null,
        tax_id: null,
        discount_id: null,
        price_list_id: null,
        split_parcel: !!document.getElementById('split-parcel').checked,
        pick_pack: !!document.getElementById('pick-pack').checked,
        ship: deliveryType === 'ship',
        carrier_id: null,
        notes: '',
        priority: 0
    };

    let quotationId = null;
    try {
        const resp = await fetch('/quotations/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(quotationData)
        });
        const data = await resp.json();
        if (resp.ok) quotationId = data.quotation_id;
        else throw new Error(data.detail || 'Failed to create quotation');
        currentOrder = data;
    } catch (e) {
        showPartnerError(e.message);
        return;
    }

    // 3. Add quotation lines (cart items)
    const lines = Object.values(cart).map(item => ({
        quantity: item.qty,
        item_id: item.id,
        price: item.price || 0,
        currency_id: item.currency_id || 1,
        cost: item.cost || 0,
        cost_currency_id: item.cost_currency_id || item.currency_id || 1
    }));
    try {
        const resp = await fetch(`/quotations/${quotationId}/lines`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(lines)
        });
        if (!resp.ok) throw new Error('Failed to add quotation lines');
    } catch (e) {
        showPartnerError(e.message);
        return;
    }

    // 4. Fetch shipping options (only after quotation is created)
    if (deliveryType === 'ship') {

        await fetchShippingRates();

    } else {
        showBuyResult('Quotation created for pickup.');
        // Optionally, proceed to payment or confirmation

        const resp = await fetch(`/partners/${partnerId}`,  { method: 'GET' });
        const partnerData = await resp.json();
        if (!resp.ok) throw new Error(partnerData.detail || 'Failed to fetch partner data');

        currentPartner = partnerData;
        currentPartner.email = partnerData.email;
        
        // Update quotation lines and show PDF preview
        // await updateQuotationPreview(quotationId, lines);
        // Fetch and show the quotation PDF again after confirming carrier
        const pdfResp = await fetch(`/quotations/${quotationId}/print`, { method: 'GET' });
        if (pdfResp.ok) {
            const blob = await pdfResp.blob();
            const url = window.URL.createObjectURL(blob);
            document.getElementById('payment-section').style.display = 'block';
            scrollToSection('payment-section');
            let previewDiv = document.getElementById('quotation-preview');
            previewDiv.innerHTML = `
                <div class="pdf-viewer-container">
                    <iframe src="${url}" class="pdf-viewer-iframe" frameborder="0"></iframe>
                </div>
            `;
            console.log(cartConfirmed, addressConfirmed);
            updateConfirmPayBtn();
            // document.getElementById('confirm-pay-btn').disabled = !(cartConfirmed && addressConfirmed);
            // document.getElementById('cancel-payment-btn').disabled = true;
        }
    }

    this.disabled = true;
    document.getElementById('cancel-address-btn').disabled = false;
    carrierConfirmed = false;
    paymentConfirmed = false; // Reset payment confirmation for new address
    showShippingOptionsIfReady();
    // Optionally, show a preview of the quotation PDF
};




// Step 3: Shipping
document.getElementById('confirm-shipping-btn').onclick = async function(e) {
    e.preventDefault();
    // Validate address section required fields
    if (!validateRequiredFields('shipping-section')) {
        showBuyResult('Please fill in all required address fields.');
        return;
    }
    // UI: Always show payment section, disable proceed, enable cancel
    document.getElementById('payment-section').style.display = 'block';
    scrollToSection('payment-section');
    this.disabled = true;
    document.getElementById('cancel-shipping-btn').disabled = false;

    // Backend logic: Only run if a shipping rate is selected
    if (!selectedShippingRate) {
        showBuyResult('Please select a shipping option.');
        return;
    }
    carrierConfirmed = true;
    updateConfirmPayBtn();
    pendingBuy = true;
    pendingCart = { ...cart };

    // Gather partner data again (in case form changed)
    const partner = getPartnerData();
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
        const quotationData = {
            partner_id: partnerData.id,
            code: '',
            currency_id: null,
            tax_id: null,
            discount_id: null,
            price_list_id: null,
            split_parcel: !!document.getElementById('split-parcel').checked,
            pick_pack: !!document.getElementById('pick-pack').checked,
            ship: document.querySelector('input[name="delivery"]:checked').value === 'ship',
            carrier_id: selectedShippingRate && selectedShippingRate.carrier_id
                ? selectedShippingRate.carrier_id
                : null,
            notes: '',
            priority: 0
        };
        const orderResp = await fetch('/quotations/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(quotationData)
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
            showPartnerError('Shipping item not found.');
            return;
        }

        // 1. Create a lot for the shipping line
        let lotId = null;
        try {
            // Generate a unique, human-readable lot_number
            const now = new Date();
            const dateStr = now.toISOString().replace(/[-:T.]/g, '').slice(0, 12);
            const carrier = selectedShippingRate.provider.replace(/\s+/g, '').toUpperCase();
            const service = selectedShippingRate.servicelevel.replace(/\s+/g, '').toUpperCase();
            const rand = Math.floor(Math.random() * 10000);
            const lotNumber = `SHIP-${carrier}-${service}-${dateStr}-${rand}`;

            const lotResp = await fetch('/lots', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    item_id: shippingItem.id,
                    lot_number: lotNumber,
                    notes: selectedShippingRate.object_id
                })
            });
            if (lotResp.ok) {
                const lotData = await lotResp.json();
                lotId = lotData.id;
            }
        } catch (err) {}

        lines.push({
            quantity: 1,
            item_id: shippingItem.id,
            price: parseFloat(selectedShippingRate.amount),
            currency_id: shippingItem.sales_currency_id || 1,
            cost: 0,
            cost_currency_id: shippingItem.cost_currency_id || shippingItem.sales_currency_id || 1,
            carrier_id: selectedShippingRate.provider,
            servicelevel: selectedShippingRate.servicelevel,
            lot_id: lotId
        });
        // 4. Update quotation lines and show PDF preview
        await updateQuotationPreview(orderId, lines);
        // Fetch and show the quotation PDF again after confirming carrier
        const pdfResp = await fetch(`/quotations/${orderId}/print`, { method: 'GET' });
        if (pdfResp.ok) {
            const blob = await pdfResp.blob();
            const url = window.URL.createObjectURL(blob);
            document.getElementById('payment-section').style.display = 'block';
            scrollToSection('payment-section');
            let previewDiv = document.getElementById('quotation-preview');
            previewDiv.innerHTML = `
                <div class="pdf-viewer-container">
                    <iframe src="${url}" class="pdf-viewer-iframe" frameborder="0"></iframe>
                </div>
            `;
            document.getElementById('confirm-pay-btn').disabled = !(cartConfirmed && addressConfirmed && carrierConfirmed);
            document.getElementById('cancel-payment-btn').disabled = false;
        }
    } catch (e) {
        showPartnerError(e.message || 'Error placing order');
    }
};

document.getElementById('cancel-address-btn').onclick = function() {
    // Hide shipping/payment section, enable proceed, disable cancel
    document.getElementById('shipping-section').style.display = 'none';
    document.getElementById('payment-section').style.display = 'none';
    document.getElementById('confirm-data-btn').disabled = false;
    this.disabled = true;
};

document.getElementById('cancel-shipping-btn').onclick = function() {
    // Hide payment section, enable proceed, disable cancel
    document.getElementById('payment-section').style.display = 'none';
    document.getElementById('confirm-shipping-btn').disabled = false;
    this.disabled = true;
};


document.getElementById('confirm-pay-btn').onclick = async function() {

        const btn = document.getElementById('confirm-pay-btn');
    if (btn) {
        if (document.querySelector('input[name="delivery"]:checked').value === 'ship') {
            btn.disabled = !(cartConfirmed && addressConfirmed && carrierConfirmed);
            document.getElementById('cancel-payment-btn').disabled = (cartConfirmed && addressConfirmed && carrierConfirmed);
        } else {
            btn.disabled = !(cartConfirmed && addressConfirmed);
            document.getElementById('cancel-payment-btn').disabled = (cartConfirmed && addressConfirmed);
        }
    }

    if (document.querySelector('input[name="delivery"]:checked').value === 'ship') {
        if (!(cartConfirmed && addressConfirmed && carrierConfirmed)) {
            showPartnerError('Please complete all previous steps before placing your order.');
            return;
        }    
    } else {
        if (!(cartConfirmed && addressConfirmed)) {
            showPartnerError('Please complete all previous steps before placing your order.');
            return;
        }    
    }

    if (!currentPartner || !currentPartner.email) {
        showPartnerError('Missing customer email.');
        return;
    }
    paymentConfirmed = true;
    // Validate required fields

    // 1. Confirm the quotation
    if (!currentOrder || !currentOrder.quotation_id) {
        showPartnerError('Missing quotation.');
        return;
    }
    let saleOrderCode = null;
    try {
        const confirmResp = await fetch(`/quotations/${currentOrder.quotation_id}/confirm`, {
            method: 'POST'
        });
        const confirmData = await confirmResp.json();
        if (!confirmResp.ok || !confirmData.sale_order_code) {
            showPartnerError(confirmData.detail || 'Failed to confirm quotation.');
            return;
        }
        saleOrderCode = confirmData.sale_order_code;
    } catch (e) {
        showPartnerError('Error confirming quotation: ' + e.message);
        return;
    }

    // 3. Create Stripe checkout session
    const payload = {
        email: currentPartner.email,
        order_number: currentOrder.code
    };
    try {
        const checkoutResp = await fetch('/create-checkout-session', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const checkoutData = await checkoutResp.json();
        if (checkoutResp.ok && checkoutData.checkout_url) {
            window.location.href = checkoutData.checkout_url;
        } else {
            showPartnerError(checkoutData.detail || 'Failed to start payment');
        }
    } catch (e) {
        showPartnerError('Error starting payment: ' + e.message);
    }
};


document.getElementById('cancel-payment-btn').onclick = function() {
    paymentConfirmed = false;
    document.getElementById('payment-section').style.display = 'none';
    this.disabled = true;
    document.getElementById('confirm-pay-btn').disabled = false;
};


document.getElementById('partner-form').onsubmit = async function(e) {
    e.preventDefault();
    if (!pendingBuy) return;
    addressConfirmed = false;

    // 1. If company order, create company first
    let companyId = null;
    if (document.getElementById('is-company').checked) {
        const company = getCompanyData();
        try {
            const resp = await fetch('/companies', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(company)
            });
            const data = await resp.json();
            if (resp.ok) companyId = data.id;
            else throw new Error(data.detail || 'Failed to create company');
        } catch (e) {
            showPartnerError(e.message);
            return;
        }
    }

    // 2. Gather partner data (shipping + billing)
    const partner = getPartnerData();
    if (companyId) partner.company_id = companyId;

    // 3. Submit partner data
    try {
        const resp = await fetch('/partners', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(partner)
        });
        const data = await resp.json();
        if (resp.ok) {
            addressConfirmed = true;
            currentPartner = data;
            // Continue with your order/quotation logic...
        } else {
            throw new Error(data.detail || 'Failed to create customer');
        }
    } catch (e) {
        showPartnerError(e.message);
        return;
    }
    // ...rest of your logic...
};


// ===============================
// Shipping & Fulfillment
// ===============================
async function fetchShippingRates() {
    // === 1. Show Loading UI at the very start ===
    document.getElementById('shipping-section').style.display = 'block';
    scrollToSection('shipping-section');
    document.getElementById('shipping-loading').style.display = 'flex';
    window.shippingOptionsDiv.style.display = 'none';
    window.shippingInfoDiv.textContent = '';

    try {
        // === 2. Get Cart Item ===
        const firstCartItem = Object.values(cart)[0];
        if (!firstCartItem) {
            window.shippingInfoDiv.textContent = 'Cart is empty.';
            document.getElementById('shipping-loading').style.display = 'none';
            return;
        }
        const itemId = firstCartItem.id;
        const orderedQuantity = firstCartItem.qty;

        // === 3. Get Vendor ID ===
        const COMPANY_OWNER_PARTNER_ID = 5; // fallback
        let vendorId = null;
        try {
            const vendorResp = await fetch(`/items/${itemId}/vendor`);
            if (vendorResp.ok) {
                const vendorData = await vendorResp.json();
                vendorId = vendorData.vendor_id;
            }
        } catch (e) {}
        if (!vendorId) {
            vendorId = COMPANY_OWNER_PARTNER_ID;
            window.shippingInfoDiv.textContent = 'Vendor not found, using company owner as vendor for shipping.';
        }

        // === 4. Ensure Customer Exists ===
        let customerId = null;
        if (currentPartner && currentPartner.id) {
            customerId = currentPartner.id;
        } else {
            const partner = getPartnerData();
            try {
                const resp = await fetch('/partners', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(partner)
                });
                const partnerData = await resp.json();
                if (resp.ok) {
                    customerId = partnerData.id;
                    currentPartner = partnerData;
                }
            } catch (e) {}
            if (!customerId) {
                window.shippingInfoDiv.textContent = 'Could not create or fetch customer.';
                document.getElementById('shipping-loading').style.display = 'none';
                return;
            }
        }

        // === 5. Carrier & Dropship Settings ===
        let carrierId = undefined;
        const vendorAcceptsDropship = 1;

        // === 6. Fetch Vendor Stock ===
        let vendorStock = null;
        try {
            const stockResp = await fetch(`/stock/${itemId}?location_type=vendor&vendor_id=${vendorId}`);
            if (stockResp.ok) {
                const stockData = await stockResp.json();
                vendorStock = stockData && stockData.length ? stockData[0].quantity : 0;
            }
        } catch (e) {}
        if (vendorStock === null) vendorStock = 0;

        // === 7. Fetch Warehouse Stock ===
        let warehouseStock = null;
        try {
            const stockResp = await fetch(`/stock/${itemId}?location_type=warehouse`);
            if (stockResp.ok) {
                const stockData = await stockResp.json();
                warehouseStock = stockData && stockData.length ? stockData[0].quantity : 0;
            }
        } catch (e) {}
        if (warehouseStock === null) warehouseStock = 0;

        // === 8. Prepare Addresses ===
        const to_address = {
            name: document.getElementById('partner-name').value,
            street1: document.getElementById('partner-street').value,
            city: document.getElementById('partner-city').value,
            state: "", // Add a field for state if needed
            zip: document.getElementById('partner-zip').value,
            country: document.getElementById('partner-country').value,
            email: document.getElementById('partner-email').value,
            phone: document.getElementById('partner-phone').value
        };

        // === 9. Fetch Vendor Address ===
        let vendorAddress = null;
        try {
            const vendorResp = await fetch(`/partners/${vendorId}`);
            if (vendorResp.ok) {
                vendorAddress = await vendorResp.json();
            }
        } catch (e) {}

        // === 10. Fetch Warehouse Address ===
        let warehouseAddress = null;
        try {
            const warehouseResp = await fetch('/partners/warehouse');
            if (warehouseResp.ok) {
                warehouseAddress = await warehouseResp.json();
            }
        } catch (e) {}

        // === 11. Fetch Shipping Costs ===
        let shippingCostVendorCustomer = null;
        if (vendorAddress) {
            try {
                const resp = await fetch('/shippo/rates', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ from_address: vendorAddress, to_address })
                });
                const data = await resp.json();
                if (resp.ok && data.rates && data.rates.length) {
                    shippingCostVendorCustomer = parseFloat(data.rates[0].amount);
                }
            } catch (e) {}
        }

        let shippingCostWarehouseCustomer = null;
        if (warehouseAddress) {
            try {
                const resp = await fetch('/shippo/rates', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ from_address: warehouseAddress, to_address })
                });
                const data = await resp.json();
                if (resp.ok && data.rates && data.rates.length) {
                    shippingCostWarehouseCustomer = parseFloat(data.rates[0].amount);
                }
            } catch (e) {}
        }

        // === 12. Decide Fulfillment Strategy ===
        let senderAddress = null;
        const fulfillmentStrategy = await fetchFulfillmentStrategy(
            itemId, vendorId, customerId, carrierId, orderedQuantity,
            vendorAcceptsDropship, warehouseStock, vendorStock,
            shippingCostVendorCustomer, shippingCostWarehouseCustomer
        );
        console.log('Fulfillment strategy:', fulfillmentStrategy);

        if (fulfillmentStrategy === "dropship") {
            senderAddress = vendorAddress;
        } else if (fulfillmentStrategy === "warehouse") {
            senderAddress = warehouseAddress;
        } else {
            showPartnerError('Please select a fulfillment strategy.');
            document.getElementById('shipping-loading').style.display = 'none';
            return;
        }

        // === 13. Fetch Final Shipping Rates ===
        try {
            const resp = await fetch('/shippo/rates', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ senderAddress, to_address })
            });
            const data = await resp.json();
            document.getElementById('shipping-loading').style.display = 'none';
            window.shippingOptionsDiv.style.display = 'block';
            // In fetchShippingRates, after fetching rates:
            if (Array.isArray(data.rates) && data.rates.length > 0) {
                window.lastShippingRates = data.rates;
                shippingRatePage = 0; // Reset to first page
                // Select cheapest carrier only on initial load
                renderShippingRates(data.rates, 'cheapest', shippingRatePage, true);
                document.querySelector('.shipping-rate-sort-btn[data-sort="cheapest"]').classList.add('active');
            } else {
                window.lastShippingRates = [];
                window.shippingInfoDiv.textContent = 'No shipping rates available.';
            }
        } catch (e) {
            document.getElementById('shipping-loading').style.display = 'none';
            window.shippingInfoDiv.textContent = 'Error fetching shipping rates.';
        }
        

    } catch (e) {
        document.getElementById('shipping-loading').style.display = 'none';
        window.shippingInfoDiv.textContent = 'Error fetching shipping rates.';
    }
}


// Helper to sort rates
function sortRates(rates, sortType) {
    if (!Array.isArray(rates)) return [];
    if (sortType === 'cheapest') {
        return [...rates].sort((a, b) => parseFloat(a.amount) - parseFloat(b.amount));
    }
    if (sortType === 'fastest') {
        return [...rates].sort((a, b) => {
            if (a.duration_terms && b.duration_terms) {
                return a.duration_terms.localeCompare(b.duration_terms);
            }
            return 0;
        });
    }
    if (sortType === 'rated') {
        return [...rates].sort((a, b) => (b.rating || 0) - (a.rating || 0));
    }
    return rates;
}

// Render rates with sorting/filtering
function renderShippingRates(rates, sortType = 'cheapest', page = 0, initiallySelectCheapest = true) {
    const shippingRateList = document.getElementById('shipping-rate-list');
    if (!shippingRateList) return;
    shippingRateList.innerHTML = '';

    // Sort rates
    const sortedRates = sortRates(rates, sortType);

    // Pagination
    const totalPages = Math.ceil(sortedRates.length / SHIPPING_RATE_PAGE_SIZE);
    const pageRates = sortedRates.slice(page * SHIPPING_RATE_PAGE_SIZE, (page + 1) * SHIPPING_RATE_PAGE_SIZE);
    pageRates.forEach((rate, idx) => {
        const globalIdx = page * SHIPPING_RATE_PAGE_SIZE + idx + 1;
        const isSelected =
            selectedShippingRate && selectedShippingRate.object_id === rate.object_id ||
            (initiallySelectCheapest && idx === 0 && sortType === 'cheapest' && page === 0);

        const card = document.createElement('div');
        card.className = 'shipping-rate-card' + (isSelected ? ' selected' : '');
        card.innerHTML = `
            <div class="shipping-rate-number">${globalIdx}.</div>
            <div class="shipping-rate-provider">${rate.provider}</div>
            <div class="shipping-rate-stars">${renderStars(rate.rating || 0)}</div>
            <div class="shipping-rate-service">${rate.servicelevel}</div>
            <div class="shipping-rate-price">${rate.amount} ${rate.currency}</div>
            <div class="shipping-rate-duration">${rate.duration_terms ? rate.duration_terms : ''}</div>
        `;
        card.onclick = function() {
            document.querySelectorAll('.shipping-rate-card').forEach(c => c.classList.remove('selected'));
            card.classList.add('selected');
            selectedShippingRate = {
                object_id: rate.object_id,
                amount: rate.amount,
                currency: rate.currency,
                provider: rate.provider,
                servicelevel: rate.servicelevel,
                duration_terms: rate.duration_terms || '',
                tax_included: rate.tax_included || false,
                rating: rate.rating || 0
            };
            updateShippingRateInfo(selectedShippingRate);
            document.getElementById('confirm-shipping-btn').disabled = false;
        };
        // Set selectedShippingRate and info only if initially selecting cheapest
        if (isSelected && initiallySelectCheapest) {
            selectedShippingRate = {
                object_id: rate.object_id,
                amount: rate.amount,
                currency: rate.currency,
                provider: rate.provider,
                servicelevel: rate.servicelevel,
                duration_terms: rate.duration_terms || '',
                tax_included: rate.tax_included || false,
                rating: rate.rating || 0
            };
            updateShippingRateInfo(selectedShippingRate);
            document.getElementById('confirm-shipping-btn').disabled = false;
        }
        shippingRateList.appendChild(card);
    });

    // Render pagination controls
    renderShippingRatePagination(totalPages, page, sortType, sortedRates);
}


function renderShippingRatePagination(totalPages, page, sortType, sortedRates) {
    const paginationDiv = document.getElementById('shipping-rate-pagination');
    if (!paginationDiv) return;
    if (totalPages <= 1) {
        paginationDiv.innerHTML = '';
        return;
    }
    paginationDiv.innerHTML = `
        <button ${page <= 0 ? 'disabled' : ''} onclick="window.shippingRatePrevPage('${sortType}')">&#8592; Prev</button>
        <span>Page ${page + 1} / ${totalPages}</span>
        <button ${page >= totalPages - 1 ? 'disabled' : ''} onclick="window.shippingRateNextPage('${sortType}')">Next &#8594;</button>
    `;
    window.shippingRatePrevPage = function(sortType) {
        if (shippingRatePage > 0) {
            shippingRatePage--;
            renderShippingRates(window.lastShippingRates, sortType, shippingRatePage, false);
        }
    };
    window.shippingRateNextPage = function(sortType) {
        const sortedRates = sortRates(window.lastShippingRates, sortType);
        const totalPages = Math.ceil(sortedRates.length / SHIPPING_RATE_PAGE_SIZE);
        if (shippingRatePage < totalPages - 1) {
            shippingRatePage++;
            renderShippingRates(window.lastShippingRates, sortType, shippingRatePage, false);
        }
    };
}

// Helper to render stars
function renderStars(rating) {
    let stars = '';
    for (let i = 1; i <= 5; i++) {
        stars += `<span>${i <= rating ? '★' : '☆'}</span>`;
    }
    return stars;
}

// Update info label below the cards
function updateShippingRateInfo(rate) {
    const infoDiv = document.getElementById('shipping-rate-info');
    if (!infoDiv || !rate) {
        infoDiv.innerHTML = '';
        return;
    }
    let priceStr = `<span class="shipping-rate-info-price">${rate.amount} ${rate.currency}</span>`;
    let taxStr = `<span class="shipping-rate-info-tax">${rate.tax_included ? 'incl. tax' : 'excl. tax'}</span>`;
    let providerStr = `<span>${rate.provider} - ${rate.servicelevel}</span>`;
    let durationStr = rate.duration_terms ? `<span style="color:#888;">${rate.duration_terms}</span>` : '';
    infoDiv.innerHTML = `
        <div class="shipping-rate-info-label">
            <h4 style="margin:0 0 8px 0;color:#1565c0;font-size:1.08rem;font-weight:600;">
                Selected Carrier Option
            </h4>
            ${priceStr} ${taxStr}<br>
            ${providerStr} ${durationStr}
        </div>
    `;
}

// Add sorting tab logic
document.querySelectorAll('.shipping-rate-sort-btn').forEach(btn => {
    btn.onclick = function() {
        document.querySelectorAll('.shipping-rate-sort-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        shippingRatePage = 0;
        renderShippingRates(window.lastShippingRates, btn.dataset.sort, shippingRatePage, false);
    };
});



// Example: Assume you have all required variables for the query
async function fetchFulfillmentStrategy(itemId, vendorId, customerId, carrierId, orderedQuantity, vendorAcceptsDropship, warehouseStock, vendorStock, shippingCostVendorCustomer, shippingCostWarehouseCustomer) {
    const params = new URLSearchParams({
        item_id: itemId,
        vendor_id: vendorId,
        customer_id: customerId,
        ordered_quantity: orderedQuantity,
        vendor_accepts_dropship: vendorAcceptsDropship,
        warehouse_stock: warehouseStock,
        vendor_stock: vendorStock
    });
    if (carrierId !== undefined && carrierId !== null && carrierId !== "undefined") {
        params.append('carrier_id', carrierId);
    }
    if (shippingCostVendorCustomer != null && shippingCostWarehouseCustomer != null) {
        params.append('shipping_cost_vendor_customer', shippingCostVendorCustomer);
        params.append('shipping_cost_warehouse_customer', shippingCostWarehouseCustomer);
    }
    const resp = await fetch(`/dropshipping-decision?${params.toString()}`);
    if (!resp.ok) throw new Error('Could not fetch fulfillment strategy');
    const data = await resp.json();
    return data.answer; // "dropship", "warehouse", or "auto"
}

async function fetchSplitParcelDecision(params) {
    // params: { number_of_items, number_of_lines, cumulative_weight, cumulative_volume, cumulative_length, cumulative_width, cumulative_height, cumulative_value, contains_hazardous_type, carrier_id, shipping_method, recipient_id, sender_id, parcel_split_allowed }
    const query = new URLSearchParams(params);
    const resp = await fetch(`/split-parcel-question?${query.toString()}`);
    if (!resp.ok) throw new Error('Could not fetch split parcel decision');
    const data = await resp.json();
    return data.answer; // e.g. "dont_split", "by_volume_LBH/5000", etc.
}

async function fetchPackingCartonDecision(params) {
    // params: { cumulative_length, cumulative_width, cumulative_height, cumulative_volume, cumulative_weight, cumulative_value, contains_hazardous, contains_hazardous_type, carrier_id, shipping_method, recipient_id, sender_id, temperature_control, fragile, insurance_required }
    const query = new URLSearchParams(params);
    const resp = await fetch(`/packing-question?${query.toString()}`);
    if (!resp.ok) throw new Error('Could not fetch packing carton decision');
    const data = await resp.json();
    return data.answer; // item_id of the chosen carton
}

// ===============================
// Quotation & Payment
// ===============================

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
        showPartnerError('Failed to update quotation lines');
        return;
    }
    const pdfResp = await fetch(`/quotations/${orderId}/print`, { method: 'GET' });
    if (pdfResp.ok) {
        const blob = await pdfResp.blob();
        const url = window.URL.createObjectURL(blob);
        // Set the iframe src in the existing payment section
        document.getElementById('payment-section').style.display = 'block';
        scrollToSection('payment-section');
        let previewDiv = document.getElementById('quotation-preview');
        previewDiv.innerHTML = `
            <div class="pdf-viewer-container">
                <iframe src="${url}" class="pdf-viewer-iframe" frameborder="0"></iframe>
            </div>
        `;
        // Enable the payment buttons as appropriate
        document.getElementById('confirm-pay-btn').disabled = !(cartConfirmed && addressConfirmed && carrierConfirmed);
        document.getElementById('cancel-payment-btn').disabled = false;
    }
    // Helper to enable/disable Place Order button
    function updateConfirmPayBtn() {
        const btn = document.getElementById('confirm-pay-btn');
        if (btn) {
            btn.disabled = !(cartConfirmed && addressConfirmed && carrierConfirmed);
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

};


// ===============================
// [SECTION NAME]
// ===============================


document.addEventListener('DOMContentLoaded', function() {
   
    // DOM elements for shipping UI
    window.shippingOptionsDiv = document.getElementById('shipping-options');
    window.shippingInfoDiv = document.getElementById('shipping-rate-info');

    document.getElementById('billing-different').onchange = function() {

        if (this.checked) {
            const delivery = document.querySelector('input[name="delivery"]:checked').value;
            if (delivery === 'ship') {
                moveElementTo('billing-fields', 'billing-fields-container-ship');
                document.getElementById('billing-fields-ship').style.display = 'block';
            } else if (delivery === 'pickup') {
                moveElementTo('billing-fields', 'billing-fields-container-pickup');
                document.getElementById('billing-fields-pickup').style.display = 'block';
            } else if (delivery === 'digital') {
                moveElementTo('billing-fields', 'billing-fields-container-pickup');
                document.getElementById('billing-fields-pickup').style.display = 'block';
            }
        } else {
            const delivery = document.querySelector('input[name="delivery"]:checked').value;
            if (delivery === 'ship') {
                moveElementTo('billing-fields', 'billing-fields-container-ship');
                document.getElementById('billing-fields-ship').style.display = 'none';
            } else if (delivery === 'pickup') {
                moveElementTo('billing-fields', 'billing-fields-container-pickup');
                document.getElementById('billing-fields-pickup').style.display = 'none';
            } else if (delivery === 'digital') {
                moveElementTo('billing-fields', 'billing-fields-container-pickup');
                document.getElementById('billing-fields-pickup').style.display = 'block';
            }
        }
    };

    document.getElementById('is-company').onchange = function() {
        const required = this.checked;
        // Toggle required attribute for company fields
        ['company-name', 'company-vat-number'].forEach(id => {
            const el = document.getElementById(id);
            if (el) el.required = required;
        });

        if (required) {
            if (document.querySelector('input[name="delivery"]:checked').value === 'pickup') {

                moveElementTo('company-fields', 'company-fields-container-pickup');
                moveElementTo('is-company-fields-container', 'settings-container-pickup');
                document.getElementById('company-fields-pickup').style.display = 'flex';

            } else if (document.querySelector('input[name="delivery"]:checked').value === 'ship') {

                moveElementTo('company-fields', 'company-fields-container-ship');
                moveElementTo('is-company-fields-container', 'settings-container-ship');
                document.getElementById('company-fields-ship').style.display = 'flex';

            } else if (document.querySelector('input[name="delivery"]:checked').value === 'digital') {

                moveElementTo('company-fields', 'company-fields-container-pickup');
                moveElementTo('is-company-fields-container', 'settings-container-pickup');
                document.getElementById('company-fields-pickup').style.display = 'flex';

            }
        } else {
            document.getElementById('company-fields-ship').style.display = 'none';
            document.getElementById('company-fields-pickup').style.display = 'none';
        }
    };

    // For pickup, always show billing fields when pickup is selected
    document.querySelectorAll('input[name="delivery"]').forEach(el => {
        el.addEventListener('change', function() {
            // 1. Reset address confirmation
            resetAddressConfirmation();

            // 2. Toggle address blocks and handle billing/company fields
            toggleAddressBlocks();
        });
    });

    // Always show shipping fields on page load (if shipping address block is visible)
    moveElementTo('shipping-fields', 'shipping-fields-container');
    moveElementTo('is-company-fields-container', 'settings-container-ship');

    loadItems();
    renderCart();
    // Call this function if you ever change the pickup address dynamically
    updatePickupMapLink("Main Warehouse", "Warehouse St 1", "12345", "City");

});


// Attach resetAddressConfirmation to all relevant address fields and checkboxes
document.querySelectorAll(
    '#address-section input, #address-section textarea'
).forEach(el => {
    el.addEventListener('input', resetAddressConfirmation);
});


document.querySelectorAll('#cart-list input, #cart-list textarea').forEach(el => {
    el.addEventListener('input', function() {
        cartConfirmed = false;
        paymentConfirmed = false;
        document.getElementById('address-section').style.display = 'none';
        document.getElementById('shipping-section').style.display = 'none';
        document.getElementById('payment-section').style.display = 'none';
    });
});



// Show billing address for pickup
function toggleAddressBlocks() {
    const delivery = document.querySelector('input[name="delivery"]:checked').value;

    // Show/hide address blocks
    document.getElementById('pickup-address').style.display = (delivery === 'pickup' || delivery === 'digital') ? 'flex' : 'none';
    document.getElementById('shipping-address-block').style.display = delivery === 'ship' ? 'flex' : 'none';

    // Billing address logic
    if (delivery === 'ship') {
        // Insert and restore shipping fields first
        moveElementTo('shipping-fields', 'shipping-fields-container');
        moveElementTo('is-company-fields-container', 'settings-container-ship');
        // Then handle billing fields
        if (document.getElementById('billing-different').checked) {
            moveElementTo('billing-fields', 'billing-fields-container-ship');
            moveElementTo('is-company-fields-container', 'settings-container-ship');
            document.getElementById('billing-fields-ship').style.display = 'block';
        }
        document.getElementById('billing-fields-pickup').style.display = 'none';

        // Company fields logic
        if (document.getElementById('is-company').checked) {
            moveElementTo('company-fields', 'company-fields-container-ship');
            moveElementTo('is-company-fields-container', 'settings-container-ship');
            document.getElementById('company-fields-ship').style.display = 'block';
        } else {
            document.getElementById('company-fields-ship').style.display = 'none';
        }

    } else if (delivery === 'pickup') {
        
        document.getElementById('warehouse-info').style.display = 'block';
        document.getElementById('billing-fields-pickup').style.display = 'block';
        moveElementTo('billing-fields', 'billing-fields-container-pickup');
        moveElementTo('is-company-fields-container', 'settings-container-pickup');
        document.getElementById('billing-fields-ship').style.display = 'none';

        // Company fields logic
        if (document.getElementById('is-company').checked) {
            moveElementTo('company-fields', 'company-fields-container-pickup');
            moveElementTo('is-company-fields-container', 'settings-container-pickup');
            document.getElementById('company-fields-pickup').style.display = 'flex';
        } else {
            document.getElementById('company-fields-pickup').style.display = 'none';
        }

    } else if (delivery === 'digital') {

        document.getElementById('warehouse-info').style.display = 'none';
        document.getElementById('billing-fields-pickup').style.display = 'block';
        moveElementTo('billing-fields', 'billing-fields-container-pickup');
        moveElementTo('is-company-fields-container', 'settings-container-pickup');
        document.getElementById('billing-fields-ship').style.display = 'none';

        // Company fields logic
        if (document.getElementById('is-company').checked) {
            moveElementTo('company-fields', 'company-fields-container-pickup');
            moveElementTo('is-company-fields-container', 'settings-container-pickup');
            document.getElementById('company-fields-pickup').style.display = 'flex';
        } else {
            document.getElementById('company-fields-pickup').style.display = 'none';
        }
    }
}

function moveElementTo(elementId, targetContainerId) {
    const formElement = document.getElementById(elementId);
    const targetContainer = document.getElementById(targetContainerId);

    // Only move if not already in the target container
    if (formElement !== null && (formElement.parentNode !== targetContainer)) {
        // Remove from current parent if necessary
        formElement.parentNode.removeChild(formElement);
        targetContainer.appendChild(formElement);
    } else {
        console.warn(`Element ${elementId} is already in container ${targetContainerId} or does not exist (element: ${JSON.stringify(formElement)}, target: ${JSON.stringify(targetContainer)}), skipping move.`);
    }
    if (formElement !== null) {
        formElement.style.display = 'block';
    }
}

function validateRequiredFields(containerId) {
    const container = document.getElementById(containerId);
    let valid = true;
    let firstInvalid = null;
    container.querySelectorAll('input[required], textarea[required]').forEach(el => {
        if (!el.value || el.value.trim() === "") {
            el.classList.add('field-error');
            valid = false;
            if (!firstInvalid) firstInvalid = el;
        } else {
            el.classList.remove('field-error');
        }
    });
    if (firstInvalid) firstInvalid.focus();
    return valid;
}

function showPartnerError(message) {
    hideBuyResult(); // Hide buy-result if showing
    const errorDiv = document.getElementById('partner-error');
    const errorMsg = document.getElementById('partner-error-message');
    errorMsg.textContent = message;
    errorDiv.style.display = 'block';

    if (partnerErrorTimeout) clearTimeout(partnerErrorTimeout);
    partnerErrorTimeout = setTimeout(hidePartnerError, 5000);
}

function hidePartnerError() {
    const errorDiv = document.getElementById('partner-error');
    errorDiv.style.display = 'none';
    const errorMsg = document.getElementById('partner-error-message');
    errorMsg.textContent = '';
    if (partnerErrorTimeout) clearTimeout(partnerErrorTimeout);
}

// Attach close button handler
document.addEventListener('DOMContentLoaded', function() {
    const closeBtn = document.getElementById('partner-error-close');
    if (closeBtn) {
        closeBtn.onclick = hidePartnerError;
    }
});

function showBuyResult(message) {
    hidePartnerError(); // Hide partner-error if showing
    const resultDiv = document.getElementById('buy-result');
    const resultMsg = document.getElementById('buy-result-message');
    resultMsg.textContent = message;
    resultDiv.style.display = 'block';

    if (buyResultTimeout) clearTimeout(buyResultTimeout);
    buyResultTimeout = setTimeout(hideBuyResult, 5000);
}

function hideBuyResult() {
    const resultDiv = document.getElementById('buy-result');
    resultDiv.style.display = 'none';
    const resultMsg = document.getElementById('buy-result-message');
    resultMsg.textContent = '';
    if (buyResultTimeout) clearTimeout(buyResultTimeout);
}

// Attach close button handler
document.addEventListener('DOMContentLoaded', function() {
    const closeBtn = document.getElementById('buy-result-close');
    if (closeBtn) {
        closeBtn.onclick = hideBuyResult;
    }
});

    
document.addEventListener('DOMContentLoaded', function() {
    // Moved from HTML <script>
    fetch('/company/name')
        .then(resp => resp.json())
        .then(data => {
        if (data.name) {
            document.title = data.name;
            const heading = document.querySelector('.shop-header h2');
            if (heading) heading.textContent = data.name;
        }
        });

    fetch('/company/address')
        .then(resp => resp.json())
        .then(data => {
        const details = document.querySelector('.pickup-address-details');
        const warehouseInfo = document.createElement('div');
        warehouseInfo.id = "warehouse-info";
        warehouseInfo.innerHTML = `
            <div class="warehouse-header">
                <img src="${data.logo_url || '/static/img/company-logo.png'}" alt="Company Logo" class="warehouse-logo">
                <div class="warehouse-header-details">
                    <h3 class="warehouse-title">${data.name || 'Main Warehouse'}</h3>
                    <div class="warehouse-address">
                        ${data.street}<br>
                        ${data.zip} ${data.city}<br>
                        ${data.country}
                    </div>
                    <div class="warehouse-contact">
                        ${data.phone ? `<span><i class="fas fa-phone"></i> ${data.phone}</span>` : ''}
                        ${data.email ? `<span><i class="fas fa-envelope"></i> ${data.email}</span>` : ''}
                        ${data.website ? `<span><i class="fas fa-globe"></i> <a href="${data.website}" target="_blank">${data.website}</a></span>` : ''}
                    </div>
                </div>
            </div>
            <div class="pickup-map-embed" style="position:relative;">
                <iframe
                    id="pickup-map-iframe"
                    width="100%"
                    height="220"
                    style="border-radius:8px;border:0;display:block;"
                    loading="lazy"
                    allowfullscreen
                    referrerpolicy="no-referrer-when-downgrade"
                    src="https://www.google.com/maps?q=${encodeURIComponent(data.street + ' ' + data.zip + ' ' + data.city + ' ' + data.country)}&output=embed"
                    onerror="showPickupMapLink()"
                ></iframe>
                <a id="pickup-map-link" href="https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(data.street + ' ' + data.zip + ' ' + data.city + ' ' + data.country)}"
                target="_blank"
                class="pickup-map-link"
                style="display:none;position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);background:#e3f2fd;padding:12px 18px;border-radius:8px;color:#1565c0;font-weight:500;text-decoration:none;">
                    <i class="fas fa-map"></i> Show on Google Maps
                </a>
            </div>
            <div id="warehouse-opening-hours" class="warehouse-opening-hours-collapsed">
                <button id="toggle-service-hours-btn" class="service-hours-toggle-btn">
                    <i class="fas fa-clock"></i> Show Service Hours & Exceptions
                </button>
                <div id="service-hours-details" style="display:none;"></div>
            </div>
            <div id="pickup-booking-block" class="pickup-booking-block"></div>
            <div id="reserved-pickup-info"></div>
            <div id="pickup-booking-controls" class="pickup-booking-controls"></div>
        `;
        const oldWarehouseInfo = details.querySelector('#warehouse-info');
        if (oldWarehouseInfo) details.removeChild(oldWarehouseInfo);
        details.prepend(warehouseInfo);

        // Call loadServiceHoursAndExceptions here, after the container exists!
        loadServiceHoursAndExceptions('CC-SLOT-001');
        loadAvailableServiceBookings('CC-SLOT-001');
        });
});


async function loadServiceHoursAndExceptions(sku) {
    try {
        const resp = await fetch(`/service-hours/${sku}`);
        if (!resp.ok) throw new Error('Could not fetch service hours');
        const data = await resp.json();
        const container = document.getElementById('warehouse-opening-hours');
        const detailsDiv = document.getElementById('service-hours-details');
        const toggleBtn = document.getElementById('toggle-service-hours-btn');
        if (!container || !detailsDiv || !toggleBtn) return;

        // Render details but keep hidden
        detailsDiv.innerHTML = `
            <h4><i class="fas fa-clock"></i> Service Hours</h4>
            ${data.hours.map(h => `
                <div class="service-hour-row">
                    <span>${h.weekday}</span>
                    <span>${h.start_time ? h.start_time : 'Closed'}${h.end_time ? ' - ' + h.end_time : ''}</span>
                </div>
            `).join('')}
            <h4><i class="fas fa-exclamation-circle"></i> Exceptions</h4>
            ${data.exceptions.length ? data.exceptions.map(e =>
                `<div class="service-exception-row">
                    <b>${e.description}</b><br>
                    ${new Date(e.start_datetime).toLocaleString()} - ${new Date(e.end_datetime).toLocaleString()}
                </div>`
            ).join('') : '<div class="service-exception-row">No exceptions</div>'}
        `;

        // Toggle logic
        toggleBtn.onclick = function() {
            if (detailsDiv.style.display === "none") {
                detailsDiv.style.display = "block";
                toggleBtn.innerHTML = `<i class="fas fa-clock"></i> Hide Service Hours & Exceptions`;
            } else {
                detailsDiv.style.display = "none";
                toggleBtn.innerHTML = `<i class="fas fa-clock"></i> Show Service Hours & Exceptions`;
            }
        };
    } catch (e) {
        const container = document.getElementById('warehouse-opening-hours');
        if (container) container.innerHTML = `<span style="color:red">Error loading service hours: ${e.message}</span>`;
    }
}

function renderPickupBookingCalendar(bookings, page = 0, filterDate = null) {
    const container = document.getElementById('pickup-booking-block');
    if (!container) return;

    // Filter by date if set
    let filtered = bookings;
    if (filterDate) {
        filtered = bookings.filter(b => {
            const start = new Date(b.start_datetime);
            return start.toISOString().slice(0,10) === filterDate;
        });
    }

    // Paginate
    const totalPages = Math.ceil(filtered.length / pickupBookingPageSize);
    const pageBookings = filtered.slice(page * pickupBookingPageSize, (page + 1) * pickupBookingPageSize);

    // Controls HTML: Jump option above navigation
    const controlsHtml = `
        <div class="pickup-booking-controls" style="flex-direction:column;align-items:center;">
            <div style="width:100%;text-align:center;margin-bottom:8px;">
                <label for="pickup-booking-date-jump" style="color:#1565c0;font-weight:500;font-size:0.98rem;margin-right:8px;">
                    Jump to date:
                </label>
                <input type="date" id="pickup-booking-date-jump" class="pickup-booking-date-jump">
                <button onclick="pickupBookingJumpDate()" class="pickup-booking-jump-btn">Go</button>
            </div>
            <div style="display:flex;justify-content:center;align-items:center;gap:8px;width:100%;">
                <button ${page <= 0 ? 'disabled' : ''} onclick="pickupBookingPrevPage()" class="pickup-booking-nav-btn">&#8592; Prev</button>
                <span style="color:#1565c0;font-size:0.97rem;">Page ${page + 1} / ${totalPages || 1}</span>
                <button ${page >= totalPages - 1 ? 'disabled' : ''} onclick="pickupBookingNextPage()" class="pickup-booking-nav-btn">Next &#8594;</button>
            </div>
        </div>
    `;

    // Calendar
    if (!pageBookings.length) {
        container.innerHTML = `
            <div style="text-align:center;margin-bottom:10px;">
                <h3 style="color:#1565c0;font-size:1.18rem;font-weight:600;margin:0 0 8px 0;">
                    Select your pickup date and time slot
                </h3>
                <div style="color:#4f8cff;font-size:0.98rem;margin-bottom:4px;">
                    Please choose a time slot for collecting your order at the warehouse.
                </div>
                ${controlsHtml}
            </div>
            <div style="color:#d32f2f;text-align:center;">No available pickup slots.</div>
        `;
        return;
    }
    container.innerHTML = `
        <div style="text-align:center;margin-bottom:10px;">
            <h3 style="color:#1565c0;font-size:1.18rem;font-weight:600;margin:0 0 8px 0;">
                Select your pickup date and time slot
            </h3>
            <div style="color:#4f8cff;font-size:0.98rem;margin-bottom:4px;">
                Please choose a time slot for collecting your order at the warehouse.
            </div>
            ${controlsHtml}
        </div>
        <div class="pickup-booking-calendar">
            ${pageBookings.map(b => {
                const isReserved = reservedPickupBooking && reservedPickupBooking.id === b.id;
                const start = new Date(b.start_datetime);
                const end = new Date(b.end_datetime);
                const options = { weekday: 'short', month: 'short', day: 'numeric' };
                const dateStr = start.toLocaleDateString(undefined, options);
                const timeStr = start.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' }) +
                    ' - ' + end.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
                return `
                    <div class="pickup-booking-slot${isReserved ? ' reserved' : ''}">
                        <span class="pickup-booking-datetime">${dateStr}</span>
                        <span>${timeStr}</span>
                        <button class="pickup-booking-btn" onclick="reservePickupBooking(${b.id})"
                            ${isReserved ? 'disabled style="background:#4f8cff;color:#fff;"' : ''}>
                            ${isReserved ? 'Reserved' : 'Reserve'}
                        </button>
                    </div>
                `;
            }).join('')}
        </div>
    `;
}

window.pickupBookingPrevPage = function() {
    if (pickupBookingPage > 0) {
        pickupBookingPage--;
        renderPickupBookingCalendar(allPickupBookings, pickupBookingPage);
    }
};
window.pickupBookingNextPage = function() {
    const totalPages = Math.ceil(allPickupBookings.length / pickupBookingPageSize);
    if (pickupBookingPage < totalPages - 1) {
        pickupBookingPage++;
        renderPickupBookingCalendar(allPickupBookings, pickupBookingPage);
    }
};
window.pickupBookingJumpDate = function() {
    const dateInput = document.getElementById('pickup-booking-date-jump');
    if (dateInput && dateInput.value) {
        // Reset to first page of filtered results
        renderPickupBookingCalendar(allPickupBookings, 0, dateInput.value);
    }
};

async function loadAvailableServiceBookings(sku) {
    try {
        const resp = await fetch(`/service-bookings/${sku}/available`);
        if (!resp.ok) throw new Error('Could not fetch available bookings');
        allPickupBookings = await resp.json();
        pickupBookingPage = 0;
        renderPickupBookingCalendar(allPickupBookings, pickupBookingPage);
    } catch (e) {
        const container = document.getElementById('pickup-booking-block');
        if (container) container.innerHTML = `<span style="color:red">Error loading bookings: ${e.message}</span>`;
    }
}

async function reservePickupBooking(bookingId) {
    // Find the booking in allPickupBookings
    const booking = allPickupBookings.find(b => b.id === bookingId);
    if (!booking) {
        showPartnerError("Slot not found.");
        return;
    }
    // Mark as reserved locally
    reservedPickupBooking = booking;
    showBuyResult("Pickup slot reserved! Please complete your address.");
    // Optionally, visually highlight the reserved slot
    renderPickupBookingCalendar(allPickupBookings, pickupBookingPage);
    // You may want to disable other booking buttons until address is filled
}

function updateReservedPickupInfo() {
    const infoDiv = document.getElementById('reserved-pickup-info');
    if (!infoDiv) return;
    if (reservedPickupBooking) {
        const start = new Date(reservedPickupBooking.start_datetime);
        const end = new Date(reservedPickupBooking.end_datetime);
        infoDiv.innerHTML = `
            <div style="background:#e3f2fd;border-radius:6px;padding:8px 12px;margin:8px 0;color:#1565c0;">
                <b>Reserved Pickup Slot:</b><br>
                ${start.toLocaleDateString()} ${start.toLocaleTimeString()} - ${end.toLocaleTimeString()}
            </div>
        `;
    } else {
        infoDiv.innerHTML = '';
    }
}

function showPickupMapLink() {
    const mapLink = document.getElementById('pickup-map-link');
    if (mapLink) mapLink.style.display = 'block';
    const mapIframe = document.getElementById('pickup-map-iframe');
    if (mapIframe) mapIframe.style.display = 'none';
}