import { useEffect, useState } from "react";
import { basketCount, subscribeBasket } from "@/lib/reviewBasket";

export function useBasketCount(): number {
  const [count, setCount] = useState(0);

  useEffect(() => {
    let active = true;
    const refresh = () => {
      basketCount().then((next) => {
        if (active) setCount(next);
      });
    };

    refresh();
    const unsubscribe = subscribeBasket(refresh);
    return () => {
      active = false;
      unsubscribe();
    };
  }, []);

  return count;
}
