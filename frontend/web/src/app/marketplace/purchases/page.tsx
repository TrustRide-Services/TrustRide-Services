import OrderList from "@/components/OrderList";

export default function Purchases() {
  return <OrderList sub="MARKETPLACE_APP" scope="PURCHASE" base="/marketplace/purchases" title="My purchases" />;
}
