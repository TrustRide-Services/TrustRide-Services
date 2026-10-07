import OrderList from "@/components/OrderList";

export default function CustomerOrders() {
  return <OrderList sub="CUSTOMER_APP" scope="SERVICE" base="/dashboard/orders" title="My orders" />;
}
