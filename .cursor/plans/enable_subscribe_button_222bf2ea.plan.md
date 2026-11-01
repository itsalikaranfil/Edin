# Enable Subscribe Button When Option Selected

## Overview
The Subscribe button is currently disabled when no product is selected or when purchasing. This plan will enable the button when one of the subscription options is selected, while keeping it disabled only during the purchasing process.

## Files to Modify

### [One/SettingsView.swift](One/SettingsView.swift)

**Location**: Subscribe button (lines ~126-137)

**Changes**:
- Modify the `.disabled()` modifier to only check `isPurchasing`
- Remove the check for `selectedProduct == nil && selectedProductID == nil`
- The button will be enabled when `selectedProduct != nil || selectedProductID != nil`
- Keep it disabled during purchase to prevent double-taps
- Update background color check to include both `selectedProduct` and `selectedProductID`

**Current code**:
```swift
Button(action: {
    purchaseSelectedProduct()
}) {
    Text("Subscribe")
        .font(.headline)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(selectedProduct != nil ? Color.black : Color.gray)
        .cornerRadius(12)
}
.disabled((selectedProduct == nil && selectedProductID == nil) || isPurchasing)
```

**New code**:
```swift
Button(action: {
    purchaseSelectedProduct()
}) {
    Text("Subscribe")
        .font(.headline)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(selectedProduct != nil || selectedProductID != nil ? Color.black : Color.gray)
        .cornerRadius(12)
}
.disabled(isPurchasing)
```

## Implementation Details

- Button is enabled when `selectedProduct != nil || selectedProductID != nil`
- Button is disabled only during the purchase process (`isPurchasing`) to prevent double-taps
- Background color updated to check both `selectedProduct` and `selectedProductID` for consistency
- The `purchaseSelectedProduct()` function already handles the case when no product is selected (returns early)
