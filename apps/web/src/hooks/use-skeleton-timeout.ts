import { useEffect, useState } from "react";

/**
 * Time-boxes loading skeletons: returns true once `ms` has elapsed so pages
 * can swap indefinite placeholders for taught empty states. Skeletons must
 * never be a terminal state ("empty states teach").
 */
export function useSkeletonTimeout(ms = 3_000): boolean {
  const [expired, setExpired] = useState(false);
  useEffect(() => {
    const id = window.setTimeout(() => setExpired(true), ms);
    return () => window.clearTimeout(id);
  }, [ms]);
  return expired;
}
